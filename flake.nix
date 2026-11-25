{
  description = "Personal MacBook nix-darwin config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, firefox-addons }:
  let
    # Username comes from the invoking user (`sudo` sets SUDO_USER), so it isn't stored in the repo.
    # Requires --impure; see README.
    username =
      let u = builtins.getEnv "SUDO_USER"; in
      if u != "" then u
      else throw "SUDO_USER is empty: run with `sudo darwin-rebuild switch --impure --flake .#macbook`";
    homeDir = "/Users/${username}";

    configuration = { pkgs, ... }:
      let
        locateDb = "/var/db/locate.database";

        # Space-separated list of directory paths to exclude from locate indexing
        # (GNU updatedb splits --prunepaths on spaces, so glob /Library/Application* instead of a literal space)
        prunePaths = builtins.concatStringsSep " " [
          "/nix/store"
          "/nix/.Trashes"
          "/System"
          "/Volumes"
          "/dev"
          "/private/tmp"
          "/tmp"
          "/private/var/vm"
          "/private/var/folders"
          "/private/var/db"
          "/private/var/protected"
          "/private/var/networkd"
          "/private/var/OOPJit"
          "/Library/Application*"
          "/Library/Caches"
          "/Library/Trial"
          "/Library/Bluetooth"
          "${homeDir}/Library"
          "${homeDir}/.Trash"
          "${homeDir}/.cache"
          "${homeDir}/.orbstack"
          "${homeDir}/.local/share/Trash"
        ];

        # Directory basenames to skip anywhere in the tree (passed to GNU find via --findoptions)
        pruneNameExpr = builtins.concatStringsSep " -o " (
          map (name: "-name ${name}") [
            ".git"
            "node_modules"
            "__pycache__"
            ".direnv"
          ]
        );

        # Wrap GNU locate & updatedb from pkgs.findutils.locate
        locateWrapper = pkgs.writeShellScriptBin "locate" ''
          exec ${pkgs.findutils.locate}/bin/locate --database="${locateDb}" "$@"
        '';

        updatedbWrapper = pkgs.writeShellScriptBin "updatedb" ''
          exec ${pkgs.findutils.locate}/bin/updatedb \
            --output="${locateDb}" \
            --prunepaths="${prunePaths}" \
            --findoptions="( ${pruneNameExpr} ) -prune -o" \
            "$@"
        '';
      in
      {
        # List packages installed in system profile. To search by name, run:
        # $ nix-env -qaP | grep wget
        environment.systemPackages = [
          pkgs.vim
          pkgs.lazygit
          pkgs.delta
          pkgs.kind
          pkgs.awscli2
          pkgs.aws-vault
          pkgs.go
          locateWrapper
          updatedbWrapper
        ];

        # Add Go & Homebrew binaries (nix-darwin already puts Nix paths ahead of /usr/bin)
        environment.systemPath = [
          "${homeDir}/go/bin"
          "/opt/homebrew/bin"
          "/opt/homebrew/sbin"
        ];

        # Set default terminal editor system-wide
        environment.variables = {
          EDITOR = "vim";
          VISUAL = "vim";
        };

        homebrew = {
          enable = true;
          onActivation.cleanup = "zap";
          brews = [
            "pi-coding-agent"
          ];
          casks = [
            "firefox"
            "visual-studio-code"
            "maccy"
            "bitwarden"
            "orbstack"
            "ghostty"
          ];
        };

        # Necessary for using flakes on this system.
        nix.settings.experimental-features = "nix-command flakes";

        # Enable default macOS shell integration in nix-darwin so systemPath & direnv load cleanly
        programs.zsh.enable = true;

        # Set Git commit hash for darwin-version.
        system.configurationRevision = self.rev or self.dirtyRev or null;

        # Used for backwards compatibility, please read the changelog before changing.
        # $ darwin-rebuild changelog
        system.stateVersion = 6;

        # The platform the configuration will be used on.
        nixpkgs.hostPlatform = "aarch64-darwin";

        system.primaryUser = username;
        users.users.${username} = {
          name = username;
          home = homeDir;
        };

        # Periodically update the GNU locate database while skipping noisy paths
        launchd.daemons.locate-updatedb = {
          serviceConfig = {
            ProgramArguments = [
              "${updatedbWrapper}/bin/updatedb"
            ];
            # Run daily at 03:00 (note: macOS skips missed calendar intervals while asleep)
            StartCalendarInterval = [
              {
                Hour = 3;
                Minute = 0;
              }
            ];
            LowPriorityIO = true;
            Nice = 10;
          };
        };

        # macOS system, keyboard & trackpad preferences
        system.defaults.NSGlobalDomain = {
          # Trackpad tracking speed / sensitivity (typically 0.0 to 3.0; adjust to taste)
          "com.apple.trackpad.scaling" = 2.0;
          # false = traditional (reversed) scrolling direction; true = macOS "Natural" scrolling
          "com.apple.swipescrolldirection" = false;

          # Disable accent popup menu so holding keys repeats instead
          ApplePressAndHoldEnabled = false;
          # Key repeat speed (lower = faster; 2 = fastest in UI, 1 = faster than UI)
          KeyRepeat = 2;
          # Delay before key repeat starts (lower = shorter; 15 = shortest in UI)
          InitialKeyRepeat = 15;
        };

        # Show battery percentage in the menu bar
        system.defaults.controlcenter = {
          BatteryShowPercentage = true;
        };

        # Maccy clipboard manager preferences
        system.defaults.CustomUserPreferences = {
          "org.p0deje.Maccy" = {
            historySize = 1000;
            pasteByDefault = true;
            ignoredApps = [
              "com.bitwarden.desktop"
            ];
          };
        };

        # Launch Maccy automatically at login
        launchd.user.agents.maccy = {
          serviceConfig = {
            ProgramArguments = [ "/Applications/Maccy.app/Contents/MacOS/Maccy" ];
            RunAtLoad = true;
            KeepAlive = false;
          };
        };

        # sudo commands using touchid
        security.pam.services.sudo_local.touchIdAuth = true;

        # Home Manager Setup inside nix-darwin
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "backup";
        home-manager.users.${username} = { pkgs, ... }: {
          programs.git = {
            enable = true;
            # Identity lives outside the repo; only applied to repos with a github.com remote
            includes = [
              {
                condition = "hasconfig:remote.*.url:git@github.com:*/**";
                path = "~/.config/git/identity";
              }
              {
                condition = "hasconfig:remote.*.url:https://github.com/**";
                path = "~/.config/git/identity";
              }
            ];
          };

          programs.direnv = {
            enable = true;
            nix-direnv.enable = true;
          };

          # Ghostty terminal configuration
          xdg.configFile."ghostty/config".text = ''
            # Treat Option key as Alt for Linux-style word navigation & deletion
            macos-option-as-alt = true

            # Native splits & tab ergonomics
            window-inherit-working-directory = true
            tab-inherit-working-directory = true
            split-inherit-working-directory = true
            unfocused-split-opacity = 0.75
            macos-titlebar-style = tabs

            # Automatically install terminfo or fall back cleanly over SSH
            shell-integration-features = ssh-terminfo,ssh-env
          '';

          # This tells Home Manager where to look for Firefox on macOS
          # since it's installed via Homebrew cask
          programs.firefox = {
            enable = true;
            package = null; # Prevents HM from trying to install the Linux app on Darwin
            profiles.myprofile = {
              id = 0;
              isDefault = true;
              # Auto-enable extensions installed by Home Manager (Firefox disables sideloaded ones by default)
              settings."extensions.autoDisableScopes" = 0;
              extensions.packages = with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
                ublock-origin
                bitwarden
                vimium
              ];
            };
          };

          home.stateVersion = "24.05"; # Version at first install; do not bump without reading HM release notes
        };
      };
  in
  {
    # Build darwin flake using:
    # $ sudo darwin-rebuild switch --impure --flake .#macbook
    darwinConfigurations.macbook = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        home-manager.darwinModules.home-manager
      ];
    };
  };
}
