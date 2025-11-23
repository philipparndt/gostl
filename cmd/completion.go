package cmd

import (
	"os"

	"github.com/spf13/cobra"
)

var completionCmd = &cobra.Command{
	Use:   "completion [bash|zsh|fish]",
	Short: "Generate shell completion script",
	Long: `Generate shell completion script for gostl.

To load completions:

Bash:

  $ source <(gostl completion bash)

  To load completions for each session, execute once:
  Linux:
    $ gostl completion bash > /etc/bash_completion.d/gostl
  macOS:
    $ gostl completion bash > /usr/local/etc/bash_completion.d/gostl

Zsh:

  If shell completion is not already enabled in your environment,
  you will need to enable it. You can execute the following once:

  $ echo "autoload -U compinit; compinit" >> ~/.zshrc

  To load completions for each session, execute once:
  $ gostl completion zsh > "${fpath[1]}/_gostl"

  You will need to start a new shell for this setup to take effect.

Fish:

  $ gostl completion fish | source

  To load completions for each session, execute once:
  $ gostl completion fish > ~/.config/fish/completions/gostl.fish
`,
	DisableFlagsInUseLine: true,
	ValidArgs:             []string{"bash", "zsh", "fish"},
	Args:                  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		switch args[0] {
		case "bash":
			rootCmd.GenBashCompletion(os.Stdout)
		case "zsh":
			rootCmd.GenZshCompletion(os.Stdout)
		case "fish":
			rootCmd.GenFishCompletion(os.Stdout, true)
		}
	},
}

func init() {
	rootCmd.AddCommand(completionCmd)
}
