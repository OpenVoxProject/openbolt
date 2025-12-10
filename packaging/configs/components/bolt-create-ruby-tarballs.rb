component "bolt-create-ruby-tarballs" do |pkg, settings, platform|
  # We only create the tarballs on Windows right now
  if platform.is_windows?
    pkg.add_source("file://resources/files/install-tarballs/extract_all.rb")
    pkg.add_source("file://resources/files/install-tarballs/remove_all.rb")
    pkg.directory "#{settings[:datadir]}/install-tarballs"
    # Unlike other examples, where the path would be '../<file>' we use the current workding directory.  This is because
    # even though we add a source as above, because it is not a gem or tar etc., the component has nothing to extract therefore
    # we don't end up in a component directory
    pkg.install_file "extract_all.rb", "#{settings[:datadir]}/install-tarballs/extract_all.rb"
    pkg.install_file "remove_all.rb", "#{settings[:datadir]}/install-tarballs/remove_all.rb"

    pkg.build do
      build_commands = []

      # Create the destination directory incase it doesn't exist already
      build_commands << "mkdir -p #{settings[:datadir]}/install-tarballs"
      build_commands << "pushd #{settings[:prefix]}"

      # Tar up the base ruby. This will exclude the ruby runtime as we need that for the extraction
      dirs = [
        "lib/ruby/gems",
      ]
      build_commands << "#{platform.tar} --create --gzip --file share/install-tarballs/ruby-#{settings[:ruby_version]}.tgz --directory=. " + dirs.join(" ")

      # We delete the source directories AFTER tarring to make debugging easier if something goes wrong.
      dirs.each { |dir| build_commands << "rm -rf #{dir}"}

      build_commands << "popd"

      build_commands
    end
  end
end
