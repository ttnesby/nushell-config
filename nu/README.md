# BUG in https://github.com/marketplace/actions/setup-nu

The `./nu` folder is a temporary solution from the action developer itself, via Discord chat.
The bug is related to which-folder awareness when nu is running. Related to https://github.com/nushell/nushell/pull/12953
