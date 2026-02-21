# Contributing

## OpenBolt Community Slack Channel

Join the `#sig-openbolt` channel in the [Vox Pupuli community
Slack](https://voxpupuli.slack.com/) where OpenBolt developers and community members
who use and contribute to OpenBolt discuss the tool.

## Issues

Please submit new issues on the GitHub issue tracker:
https://github.com/OpenVoxProject/openbolt/issues

Choose the appropriate template depending on the kind of issue you're filing:
feature request, bug report, or docs change.

## Types of Improvements

The OpenBolt ecosystem is extensible via Puppet modules such as those hosted on the
[Forge](https://forge.puppet.com/). Many improvements to the OpenBolt ecosystem
can be added there as new modules, including [Bolt
tasks](https://puppet.com/docs/bolt/latest/writing_tasks.html), [Bolt
plans](https://puppet.com/docs/bolt/latest/writing_yaml_plans.html), [inventory
plugins](https://puppet.com/docs/bolt/latest/writing_plugins.html),
and [Puppet functions](https://puppet.com/docs/puppet/latest/writing_custom_functions.html). Please
consider if your use case can be solved with one of these tools before modifying OpenBolt itself.

There are certain types of improvements that we believe make sense in OpenBolt
itself:

* New Transports. The transports API is a work-in-progress, but is something we
  aim to stabilize. Currently, transports can't be extended via modules, although
  in the future they likely will be.
* Core functionality we believe makes OpenBolt a better tool, such as the
  `aggregate` and `canary` plans included in `modules`.
* New core functions
    * New functions that use OpenBolt internals such as the Executor,
      Applicator, or Inventory should live in bolt-modules/boltlib.
    * Other directories under bolt-modules are used to categorize OpenBolt's
      standard library functions.
* New ways of interacting with plan progress and output, such as prompts to
  continue or output processors.

## Pull Requests

Pull requests are welcome on GitHub: https://github.com/OpenVoxProject/openbolt

**If this is your first time submitting a PR**:
1. Fork the OpenBolt project (button in the top-right, next to 'star' and 'watch')
1. Clone your fork of OpenBolt
1. Add the OpenVoxProject repo as an upstream - `git remote add upstream
   git@github.com:openvoxproject/openbolt`
1. Make a new branch off of main - `git checkout -b mybranchname`
1. Commit your changes and add a useful commit message, including what
   specifically you changed and why - `git commit`
    * If your changes are user-facing, add a release note to the end of a commit
      message. Release notes should begin with a label indicating what kind of
      change you are making. Valid labels include `!feature`, `!bug`,
      `!deprecation`, and `!removal`.

      Release notes should follow this format:

      ```
      !label

      * **Descriptive title of changes** ([#issue_number](issue_url))

        Descriptive summary of changes.
      ```
1. Push your changes to your branch on your fork - `git push origin
   mybranchname`
1. Open a PR against main at https://github.com/OpenVoxProject/openbolt
1. Ensure tests pass

**If it's not your first PR:**
1. Update from upstream:
   ```
   git fetch upstream && git checkout upstream/main && git checkout -b mybranchname
   ```
1. Commit your changes and add a useful commit message, including what
   specifically you changed and why - `git commit`
1. Push your changes to your branch on your fork - `git push origin
   mybranchname`
1. Open a PR against main at https://github.com/OpenVoxProject/openbolt

Once you've opened a PR the Vox Pupuli OpenBolt team will automatically be notified. We're a small team, but we do
our best to review PRs in a timely manner.

## Installing OpenBolt

If you are interested in trying OpenBolt out or using it in production, we recommend
installing from a system package detailed in [Installing
Bolt](https://puppet.com/docs/bolt/latest/bolt_installing.html). The following
installation instructions are focused on developers who wish to contribute to
OpenBolt.

Depending on your development workflow, you can install OpenBolt one of three ways:

* From [RubyGems](https://rubygems.org)
* From your Gemfile with Bundler
* From source

OpenBolt vendors a version of OpenVox that supports executing tasks and plans, so you
do not need to install OpenVox or Puppet. If you happen to already have OpenVox or Puppet installed,
then the vendored version takes precedence and does not conflict with the
already installed version.

### RubyGems install

To install from [RubyGems](https://rubygems.org), run:

    gem install openbolt

### Bundler install

To use [Bundler](https://bundler.io), add this to your Gemfile:

    gem 'openbolt'

### Run OpenBolt from source

To run OpenBolt from source:

    bundle install --path .bundle --without test
    bundle exec bolt ...

To use `rubocop`, perform the bundle install with no exclusions

    bundle install --path .bundle --with test
    bundle exec rake rubocop

### Contributing to bundled modules

Some module content is included with the Bolt gem for out-of-the-box use. Some
of those modules are included in this repository and others are managed with the
Puppetfile included in this repository. All the bundled modules are installed in
the `modules` directory.

To change external modules (to add a new module or bump the version), update the
Puppetfile and then run `bundle exec r10k puppetfile install`.

## Testing

### Provisioning for *nix tests

For Linux tests (recommended, if you're not sure), you'll need to have Docker installed to provision
container infrastructure locally to test against. Once that's are installed, run the following from
the root of the Bolt repo:

```
docker-compose -f spec/docker-compose.yml up -d --build
```

### Provisioning for Windows tests
For Windows tests, execute `vagrant up` from the root of the Bolt repo to bring these up with the
provided Vagrantfile. Any tests that require this are tagged with `:winrm` or `:ssh` in rspec.

Additional tests might run in a local environment and require certain shell
capabilities. For example, tests that require a Bash-like environment are tagged
with `:bash` in rspec.

Some tests will also require that the [bundled
modules](#contributing-to-bundled-modules) described above are installed. Ensure
the modules are installed for testing with the following command:

    $ bundle exec r10k puppetfile install .

To run all tests, run:

    $ bundle exec rake spec

To exclude tests that rely on Vagrant, run:

    $ bundle exec rake tests:unit

To run specific versions of tagged tests, run the `tests` target with the tag
appended:

    $ bundle exec rake tests:bash

You can view a full list of available tasks that run tests with:

    $ bundle exec rake -T

Windows includes additional tests that require a full Windows Server VM to run.
If you need to run the tests locally, set `WINDOWS_AGENTS=true`, re-run `vagrant
up` to create a `Windows Server 2016 Core` VM, and run tests with

    $ BOLT_WINRM_PORT=35985 BOLT_WINRM_SMB_PORT=3445 BOLT_WINRM_USER=vagrant BOLT_WINRM_PASSWORD=vagrant bundle exec rake ci:windows:agentful

## Security Auditing

OpenBolt includes [bundler-audit](https://github.com/rubysec/bundler-audit) and
[ruby_audit](https://github.com/civisanalytics/ruby_audit) for scanning gem
dependencies and the Ruby runtime against known CVEs.

### Running locally

Install the audit gems (included in the `:audit` Gemfile group) and run:

    $ bundle exec bundler-audit check --update
    $ bundle exec ruby-audit check

`bundler-audit` scans the `Gemfile.lock` against the
[ruby-advisory-db](https://github.com/rubysec/ruby-advisory-db).
`ruby-audit` checks the running Ruby and RubyGems versions for known
vulnerabilities.

### CI workflow

The `.github/workflows/audit.yaml` workflow runs both tools automatically:

- On pull requests and pushes to `main` when `Gemfile`, `Gemfile.lock`, or
  `*.gemspec` files change.
- On a weekly schedule (Monday 08:00 UTC) to catch newly disclosed advisories.
- Via manual dispatch.

The workflow is **non-blocking** — vulnerabilities are reported in the GitHub
Actions job summary but do not prevent merges. This allows the team to triage
and address findings without halting development.

### `rubocop` on Windows

To use `rubocop` on Windows, you must have a ruby install with a configured
devkit and the MSYS2 base package in order to compile ruby C extensions. This
can be downloaded from https://rubyinstaller.org/downloads/ or installed using
[chocolatey](https://chocolatey.org/packages/ruby)

    choco install ruby
    refreshenv
    ridk install    # Choose the base install and complete the Wizard selections.
