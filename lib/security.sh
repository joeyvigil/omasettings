#!/bin/bash
# Security: sudo behaviour, biometric auth, and system snapshots.
# Everything here needs sudo, so these run attached to the terminal.

_sec_nopasswd_state() {
  # omarchy-sudo-passwordless drops a sudoers file and arms a systemd timer to
  # remove it again; the timer is readable without sudo, the file is not.
  systemctl is-active "omarchy-nopasswd-expire-${USER}.timer" >/dev/null 2>&1 &&
    printf 'on' || printf 'off'
}

_sec_snapshots() {
  while true; do
    oma_screen "System › Snapshots"

    if ! oma_has snapper; then
      oma_err "snapper is not installed — snapshots are unavailable"
      oma_dim "They require a Btrfs root configured at install time."
      oma_pause
      return 1
    fi

    local choice
    choice=$(oma_select "System snapshots (snapper)" \
      $'create\tCreate a snapshot now\t' \
      $'restore\tRestore a snapshot\t' \
      $'list\tList snapshots\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    create) oma_exec "Snapshot created" omarchy snapshot create ;;
    restore)
      oma_screen "System › Snapshots"
      oma_warn "Restoring rolls the system back to an earlier state."
      printf '\n'
      oma_confirm "Continue to snapshot restore?" &&
        oma_exec "Snapshot restored" omarchy snapshot restore
      ;;
    list)
      oma_screen "System › Snapshots"
      sudo snapper list 2>&1 | gum pager || true
      ;;
    back | *) return 0 ;;
    esac
  done
}

security_menu() {
  while true; do
    oma_screen "System › Security"

    local choice
    choice=$(oma_select "Sudo, biometrics, and snapshots" \
      "$(printf 'nopasswd\tPasswordless sudo\t%s' "$(_sec_nopasswd_state)")" \
      $'keepalive\tKeep sudo alive in the background\t' \
      $'reset\tReset sudo lockout\t' \
      $'fingerprint\tSet up fingerprint unlock\t' \
      $'fido2\tSet up a FIDO2 security key\t' \
      $'drivepw\tChange drive encryption password\t' \
      $'snapshots\tSystem snapshots…\t' \
      "$OMA_BACK") || return 0

    case "$choice" in
    nopasswd)
      oma_screen "System › Security"
      if [[ $(_sec_nopasswd_state) == on ]]; then
        oma_dim "Passwordless sudo is currently active."
        printf '\n'
        oma_confirm "Turn passwordless sudo off?" || continue
        oma_exec "Passwordless sudo disabled" omarchy sudo passwordless
      else
        oma_warn "This lets any process run sudo without a password."
        oma_dim "It expires automatically after the number of minutes you choose."
        printf '\n'
        local mins
        mins=$(gum input --header "Enable for how many minutes?" --value "15") || continue
        [[ $mins =~ ^[0-9]+$ ]] || {
          oma_err "not a number"
          oma_pause
          continue
        }
        oma_exec "Passwordless sudo enabled for ${mins}m" omarchy sudo passwordless "$mins"
      fi
      ;;
    keepalive) oma_exec "Sudo credential refreshed" omarchy sudo keepalive ;;
    reset) oma_exec "Sudo lockout reset" omarchy sudo reset ;;
    fingerprint) oma_exec "Fingerprint configured" omarchy setup security fingerprint ;;
    fido2) oma_exec "FIDO2 configured" omarchy setup security fido2 ;;
    drivepw)
      oma_screen "System › Security"
      oma_warn "This changes the LUKS passphrase for your encrypted drive."
      printf '\n'
      oma_confirm "Continue?" && oma_exec "Drive password changed" omarchy drive password
      ;;
    snapshots) _sec_snapshots ;;
    back | *) return 0 ;;
    esac
  done
}
