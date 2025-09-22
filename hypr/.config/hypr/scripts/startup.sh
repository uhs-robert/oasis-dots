#!/usr/bin/env bash
# hypr/.config/hypr/scripts/startup.sh

# ========== CONFIG ========== #

TIMEOUT=30
WAIT_SECONDS=1
RUN_TIME=0
IS_DISPLAY_READY=false
IS_MONITOR_READY=false
IS_FLATPAK_READY=false
EXPECTED_MONITOR_COUNT=4

# ========== UTLITY ========== #

# Log to journal and echo
log() {
  echo "$1"
  logger -t hypr-startup "$1"
}

# ========== LOGIC ========== #

# Graphic dependent startup
graphic_dependent() {
  is_ready() {
    while ! hyprctl activewindow &>/dev/null; do
      sleep $WAIT_SECONDS
      ((RUN_TIME += WAIT_SECONDS))
    done
    IS_DISPLAY_READY=true
    log "[Display] Is ready"
  }

  run_tasks() {
    before() {
      # log "[Display] Before hook..."
      :
    }

    ready() {
      log "[Display] Main hook..."
      ~/.config/hypr/scripts/assign-workspaces.sh --watch &
    }

    not_ready() {
      log "[Display] Warning - Error hook..."
    }

    after() {
      # log "[Display] After hook..."
      :
    }

    before

    if [[ "$IS_DISPLAY_READY" == true ]]; then
      ready
    else
      not_ready
    fi

    after
  }
  is_ready
  run_tasks
}

# Monitor dependent startup
monitor_dependent() {
  is_ready() {
    local EXPECTED_MONITOR_COUNT=4
    while ((RUN_TIME < TIMEOUT)); do
      MONITOR_COUNT=$(hyprctl monitors -j | jq length)
      if ((MONITOR_COUNT >= EXPECTED_MONITOR_COUNT)); then
        IS_MONITOR_READY=true
        log "[Monitors] Is ready - # Monitors detected: $MONITOR_COUNT"
        sleep $WAIT_SECONDS
        ((RUN_TIME += WAIT_SECONDS))
        break
      fi
      sleep $WAIT_SECONDS
      ((RUN_TIME += WAIT_SECONDS))
    done
  }

  run_tasks() {
    before() {
      # log "[Monitors] Before hook..."
      :
    }

    ready() {
      # log "[Monitors] Main hook..."
      :
    }

    not_ready() {
      log "[Monitors] Warning - Error hook..."
      ~/.config/hypr/scripts/assign-workspaces.sh --assign
    }

    after() {
      log "[Monitors] After hook..."
      ~/.config/hypr/scripts/hypr-wallpaper.sh &
      hyprctl setcursor Breeze 24 & # Mouse cursor
      :
    }

    before

    if [[ "$IS_MONITOR_READY" == true ]]; then
      ready
    else
      not_ready
    fi

    after
  }
  is_ready
  run_tasks
}

# Application dependent startup
application_dependent() {
  is_ready() {
    while ((RUN_TIME < TIMEOUT)); do
      if flatpak list &>/dev/null; then
        log "[Flatpak] Is ready"
        IS_FLATPAK_READY=true
        return
      fi
      log "[Flatpak] Waiting for service to load..."
      sleep $WAIT_SECONDS
      ((RUN_TIME += WAIT_SECONDS))
    done

    log "[Flatpak] Not ready after $TIMEOUT seconds — continuing anyway"
  }

  run_tasks() {
    before() {
      # log "[Flatpak] Before hook..."
      :
    }

    ready() {
      log "[Flatpak] Main hook..."
      ~/.config/hypr/scripts/auto-launch-apps.sh --startup
    }

    not_ready() {
      log "[Flatpak] Warning - Error hook..."
    }

    after() {
      # log "[Flatpak] After hook..."
      :
    }

    before

    if [[ "$IS_FLATPAK_READY" == true ]]; then
      ready
    else
      not_ready
    fi

    after
  }
  is_ready
  run_tasks
}

# ========== MAIN ========== #
main() {
  graphic_dependent
  monitor_dependent
  application_dependent
}

# ========== START ========== #
main
