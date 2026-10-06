# NixOS Config

This repository contains my personal NixOS configuration files.
I am still learning nix and am aware that some refactoring is needed, especially
to decouple the machine-specific config (e.g. "this is what I want on this specific machine")
from the more general, more imortable configuration.

You almost certainly don't want to take this and build it on your own machine.
I am sharing it for educational purposes and because I was asked to do so.

Firefox and Zen are both managed by Home Manager, with shared extensions,
search engines, preferences, and policies in `modules/home/firefox/common.nix`.
Zen-specific preferences stay in `modules/home/zen-browser/default.nix`.
Each browser keeps its own profile; adding Firefox does not migrate Zen data
or change the default browser.
