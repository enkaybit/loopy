package main

import (
	"os"

	"github.com/enkaybit/loopy/tools/loopy-taskd/internal/cli"
)

func main() {
	os.Exit(cli.Execute(os.Args[1:], os.Stdout, os.Stderr))
}
