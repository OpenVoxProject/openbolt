#!/usr/bin/env ruby

require 'puppet_metadata'
require 'semantic_puppet'

def normalize_name(name)
  name.tr('-', '/')
end

class LocalModules < SemanticPuppet::Dependency::Source
  attr_reader :modules

  def initialize(module_dirs)
    @modules = {}

    module_dirs.each do |module_dir|
      Dir[File.join(module_dir, '*', 'metadata.json')].sort.map do |metadata|
        mod = PuppetMetadata.read(metadata)
        dependencies = mod.dependencies.map { |name, requirement| [normalize_name(name), requirement.to_s] }
        name = normalize_name(mod.name)
        @modules[name] = create_release(name, mod.version, dependencies)
      rescue PuppetMetadata::InvalidMetadataException => e
        raise "#{metadata}: #{e}"
      end
    end

    @modules.freeze
  end

  def fetch(name)
    if @modules.key?(name)
      [@modules[name]]
    else
      []
    end
  end
end

class ProvidedModules < SemanticPuppet::Dependency::Source
  attr_reader :modules

  def initialize(modules)
    @modules = {}

    modules.each do |name, version|
      name = normalize_name(name)
      @modules[name] = create_release(name, version)
    end

    @modules.freeze
  end

  def fetch(name)
    if @modules.key?(name)
      [@modules[name]]
    else
      []
    end
  end
end

# TODO: read this from environment.conf
local_source = LocalModules.new(['modules'])
SemanticPuppet::Dependency.add_source(local_source)

modules = Hash[local_source.modules.map { |name, mod| [name, mod.version.to_s] }]

graph = SemanticPuppet::Dependency.query(modules)
begin
  releases = SemanticPuppet::Dependency.resolve(graph)
  puts "Satisfied all dependencies:"
  releases.each do |release|
    # TODO: print source
    puts "  #{release.name} #{release.version}"
  end
rescue SemanticPuppet::Dependency::UnsatisfiableGraph => e
  # There was some dependency that wasn't matched. We know its name and that
  # it's a dependency we requested previously. Now to investigate why to
  # provide useful hints

  # TODO: it's *very* weird to store unsatisfiable in a module
  # Strange API
  unsatisfiable = SemanticPuppet::Dependency.unsatisfiable

  unless unsatisfiable
    # In older semantic_puppet unsatisfiable was unreliable
    # Needs https://github.com/puppetlabs/semantic_puppet/pull/37
    warn e
    warn "semantic_puppet provides insufficient information to hint why"
    exit 1
  end

  warn "Unable to satisfy #{unsatisfiable}"

  releases = graph.dependencies[unsatisfiable]
  if releases.empty?
    # This should never happen
    warn "No releases found for #{unsatisfiable}"
    exit 2
  end

  releases.each do |release|
    warn "Investigating version #{release.version}"
    unsatisfied = release.dependencies.select { |_, candidates| candidates.empty? }
    if unsatisfied.empty?
      # Is this ever the case, did we miss anything else?
      warn "  All dependencies satisfied"
    else
      unsatisfied.each do |dependency, _|
        constraint = release.constraints_for(dependency).find { |constraint| constraint[:source] == 'initialize' }
        warn "  Dependency #{dependency} (#{constraint[:description]}) can't be satified"

        constraint_graph = SemanticPuppet::Dependency.query(dependency => '>= 0')
        begin
          releases = SemanticPuppet::Dependency.resolve(constraint_graph)
          mod_releases = releases.select { |release| release.name == dependency }
          warn "    Available versions: #{mod_releases.map { |r| r.version }.join(', ')}"
        rescue SemanticPuppet::Dependency::UnsatisfiableGraph
          warn "    Unable to find any release"
        end
      end
    end
  end

  exit 3
end
