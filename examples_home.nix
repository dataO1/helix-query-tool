# Example Home Manager Configuration
{ config, lib, pkgs, helix-indexer, ... }:

{
  # Enable HelixDB search integration
  services.helix-search = {
    enable = true;
    
    # Suggest paths for user-level indexing
    searchPaths = [ 
      "$HOME/Documents"
      "$HOME/Projects" 
      "$HOME/.config"
      "$HOME/Notes"
    ];
    
    # Custom shell aliases
    aliases = {
      "hs" = "helix-search";
      "hsf" = "helix-search --files";
      "hsc" = "helix-search --code-only";
      "hsd" = "helix-search --directory $HOME/Documents";
      "hsp" = "helix-search --directory $HOME/Projects";
      "search-notes" = "helix-search --directory $HOME/Notes --filetype md";
      "search-config" = "helix-search --directory $HOME/.config";
    };
  };

  # Additional packages for enhanced search experience
  home.packages = with pkgs; [
    # Text processing tools that work well with search results
    ripgrep          # For follow-up searches
    fd               # File finding
    bat              # Syntax highlighting for file preview
    fzf              # Fuzzy finding
    jq               # JSON processing
    
    # Development tools that benefit from semantic search
    tree-sitter      # Syntax parsing (when available)
  ];

  # Shell integration
  programs.bash = {
    enable = true;
    
    # Custom functions for advanced search workflows
    bashrcExtra = ''
      # Search and edit function
      search-edit() {
        local result=$(helix-search "$@" | grep -E "^[0-9]+\." | head -1)
        if [[ -n "$result" ]]; then
          local filepath=$(echo "$result" | sed -n 's/^[0-9]*\. \([^(]*\).*/\1/p')
          $EDITOR "$filepath"
        else
          echo "No results found"
        fi
      }
      
      # Search and cd to directory
      search-cd() {
        local result=$(helix-search --files "$@" | grep -E "^[0-9]+\." | head -1)
        if [[ -n "$result" ]]; then
          local filepath=$(echo "$result" | sed -n 's/^[0-9]*\. \([^(]*\).*/\1/p')
          cd "$(dirname "$filepath")"
        else
          echo "No files found"
        fi
      }
      
      # Quick search in current project
      search-project() {
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          local project_root=$(git rev-parse --show-toplevel)
          helix-search --directory "$project_root" "$@"
        else
          helix-search --directory "$PWD" "$@"
        fi
      }
    '';
  };

  programs.zsh = {
    enable = true;
    
    # Zsh-specific enhancements
    initExtra = ''
      # Auto-completion for helix-search
      compdef _gnu_generic helix-search
      
      # Keybinding for quick search
      bindkey -s '^Xs' 'helix-search '
      
      # Widget for searching and inserting filepath
      search-insert-path() {
        local result=$(helix-search --files "''${BUFFER}" | head -1 | sed -n 's/^[0-9]*\. \([^(]*\).*/\1/p')
        if [[ -n "$result" ]]; then
          BUFFER="$result"
          CURSOR=$#BUFFER
        fi
        zle redisplay
      }
      zle -N search-insert-path
      bindkey '^Xf' search-insert-path
    '';
  };

  programs.fish = {
    enable = true;
    
    # Fish shell functions
    functions = {
      search-edit = "helix-search $argv | head -1 | string replace -r '^[0-9]+\\. ([^(]*).*' '$1' | xargs $EDITOR";
      search-cd = "helix-search --files $argv | head -1 | string replace -r '^[0-9]+\\. ([^(]*).*' '$1' | xargs dirname | xargs cd";
      search-project = ''
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1
          helix-search --directory (git rev-parse --show-toplevel) $argv
        else
          helix-search --directory $PWD $argv
        end
      '';
    };
  };

  # Git integration for better search context
  programs.git = {
    enable = true;
    
    aliases = {
      # Search for files that were recently modified
      "search-recent" = "!f() { git diff --name-only HEAD~\${1:-10} | xargs -I {} helix-search --files {}; }; f";
      # Search in files that match a git pattern
      "search-grep" = "!f() { git ls-files | grep \$1 | xargs helix-search \$2; }; f";
    };
  };

  # Editor integration
  programs.neovim = {
    enable = true;
    
    extraConfig = ''
      " Quick search command in Neovim
      command! -nargs=* HelixSearch :!helix-search <args>
      nnoremap <leader>s :HelixSearch<space>
      
      " Search for word under cursor
      nnoremap <leader>sw :execute '!helix-search ' . expand('<cword>')<CR>
      
      " Search in current file type
      nnoremap <leader>st :execute '!helix-search --filetype ' . &filetype<CR>
    '';
  };

  # VS Code integration (if using VS Code)
  programs.vscode = {
    enable = true;
    
    keybindings = [
      {
        key = "ctrl+shift+s";
        command = "workbench.action.terminal.sendSequence";
        args = {
          text = "helix-search ";
        };
      }
    ];
  };

  # Desktop integration
  services.polybar = {
    enable = true;
    
    config = {
      "module/search" = {
        type = "custom/script";
        exec = "echo 🔍";
        click-left = "kitty -e helix-search";
        format-foreground = "#61afef";
      };
    };
  };

  # Notification integration for indexing updates
  services.dunst = {
    enable = true;
    
    settings = {
      global = {
        follow = "mouse";
        format = "<b>%s</b>\\n%b";
      };
      
      urgency_normal = {
        background = "#285577";
        foreground = "#ffffff";
        timeout = 5;
      };
    };
  };

  # Custom configuration file
  xdg.configFile."helix-search/config.yaml".text = ''
    # HelixDB connection
    helix_db:
      host: "localhost"
      port: 6969
      timeout: 30

    # CLI preferences  
    cli:
      default_limit: 15
      highlight_results: true
      show_line_numbers: true
      compact_output: false
      
    # Search paths (user-specific)
    search_paths:
      - "~/Documents"
      - "~/Projects"
      - "~/.config"
      - "~/Notes"
      
    # Custom file type mappings
    file_types:
      ".nix": "nix"
      ".md": "markdown" 
      ".py": "python"
      ".rs": "rust"
      ".go": "go"
      ".js": "javascript"
      ".ts": "typescript"
      
    # Search result formatting
    formatting:
      max_preview_lines: 4
      show_file_icons: true
      color_scheme: "dark"
  '';
}