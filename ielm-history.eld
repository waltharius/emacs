(hugo--determine-category 
  "~/notes/20251209T003729--essential-tmux-keybindings-quick-reference__docu_en_hugosync_linux_tmux.org")
exit
quit
(hugo--determine-category 
  "~/notes/20251209T003729--essential-tmux-keybindings-quick-reference__docu_en_hugosync_linux_tmux.org")
;; Should return: "tools" (not "systems"!)

;; Test an emacs file
(hugo--determine-category 
  "~/notes/20251112T030951--do-poprawy-w-moim-systemie-notowania-emacs__docu_emacs_hugosync.org")
;; Should return: "tools"

;; Test a NixOS file
(hugo--determine-category 
  "~/notes/20251226T151848--nixos-from-scratch__btrfs_docu_en_hugosync_linux_nixos.org")
;; Should return: "systems"

;; Test a proxmox file  
(hugo--determine-category 
  "~/notes/20251111T182255--proxmox__docu_homelab_hugosync_linux_proxmox.org")
;; Should return: "infrastructure"
exit
help
?
/?
