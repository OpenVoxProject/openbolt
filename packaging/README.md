# OpenBolt Vanagon Packaging

This project uses [vanagon](https://github.com/OpenVoxProject/vanagon) to generate
installable packages for [OpenBolt](https://github.com/OpenVoxProject/openbolt).

Not all OpenBolt dependencies are configured here:

- Dependencies shared between this and other vanagon projects are loaded from
  [puppet-runtime](https://github.com/OpenVoxProject/puppet-runtime)'s openbolt-runtime project.
- Dependencies specific to OpenBolt are configured in this project. However, puppet-runtime now
  contains some OpenBolt-specific dependencies too. Our intention is to move those into this repo
  at some point.

## Run the project

```
bundle install
bundle exec build openbolt el-10-x86_64
```

If the packaging works, it will place a package in the `packaging/output/` folder.
