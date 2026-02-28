# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

Each top-level directory is a stow package that mirrors the target filesystem structure.

```bash
stow <package>        # deploy a package
stow -D <package>     # remove a package
```
