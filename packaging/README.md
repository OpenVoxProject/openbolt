# Bolt Vanagon Project

- Puppet Labs [vanagon](https://github.com/puppetlabs/vanagon)

## Updating rubygem versions

A script has been provided to help updating versions of existing gems. Run as
```
./generate.rb /path/to/bolt/Gemfile.lock
```

It will skip gems that are not currently managed (i.e. don't have a `rubygem-*.rb` file) to avoid
adding gems provided by bolt-runtime or that are unneeded. New gems must be manually added, which
can be as simple as `touch configs/components/rubygem-<newgem>.rb`.

Gems that have not yet been mirrored internally will also not be updated. The script will provide
the command to run to update them in the `release-new` HipChat room. For example
```
Could not update foo, please mirror with: !mirrorsource https://rubygems.org/downloads/foo-0.0.1.gem
```
After mirroring gems, rerun the script to update their component configs.

## Run the project

```
bundle install
bundle exec build puppet-bolt el-7-x86_64
```

If the packaging works, it will place a package in the `output/` folder.
