# Bolt documentation

This directory contains the ERB templates used to generate reference documentation
for OpenBolt. Static documentation pages live in the
[openvox-docs](https://github.com/OpenVoxProject/openvox-docs) repository.

## Generated reference documentation

Several reference pages are generated from Bolt's source code. Each has an ERB
template in the [templates](./templates) directory and a corresponding rake task in
[rakelib/docs.rake](../rakelib/docs.rake).

Generate all reference pages:

```shell
bundle exec rake docs:all
```

Generate Jekyll-ready output (rendered templates + `.md` links rewritten to `.html`):

```shell
bundle exec rake docs:jekyll
```

Output is written to `documentation/jekyll_build/` (gitignored). The openvox-docs
copy pipeline runs `rake docs:jekyll` and copies this directory to pick up the
reference pages.

## Reference pages and their templates

| Page | Template | Rake task |
| ---- | -------- | --------- |
| Shell command reference | `templates/bolt_command_reference.md.erb` | `docs:command_reference` |
| PowerShell cmdlet reference | `templates/bolt_cmdlet_reference.md.erb` | `docs:cmdlet_reference` |
| Plan functions | `templates/plan_functions.md.erb` | `docs:function_reference` |
| `bolt-defaults.yaml` options | `templates/bolt_defaults_reference.md.erb` | `docs:defaults_reference` |
| `bolt-project.yaml` options | `templates/bolt_project_reference.md.erb` | `docs:project_reference` |
| Transport configuration | `templates/bolt_transports_reference.md.erb` | `docs:transports_reference` |
| Privilege escalation | `templates/privilege_escalation.md.erb` | `docs:privilege_escalation` |
| Bolt data types | `templates/bolt_types_reference.md.erb` | `docs:type_reference` |
| Packaged modules | `templates/packaged_modules.md.erb` | `docs:packaged_modules` |
