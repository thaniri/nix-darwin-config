# nix-darwin config

## Personal info

- Not stored in the repo
- Username: read from `SUDO_USER` at build time → needs `sudo` + `--impure`
- Home dir: `/Users/<username>`
- Git name/email: `~/.config/git/identity` (local file, see below)

## Fresh Mac setup

- Install Nix
- Install Homebrew
- Clone repo to `~/.config/nix-darwin-config`
- First build (`darwin-rebuild` isn't installed yet):
  ```sh
  cd ~/.config/nix-darwin-config
  sudo nix run nix-darwin/master#darwin-rebuild -- switch --impure --flake .#macbook
  ```

## After first build

- Create `~/.config/git/identity` (only used for github.com):
  ```ini
  [user]
      name = ...
      email = ...
  ```

## Day to day

- Rebuild: `sudo darwin-rebuild switch --impure --flake ~/.config/nix-darwin-config#macbook`
- Update inputs: `nix flake update`
- `git add` new files — flakes ignore untracked files
