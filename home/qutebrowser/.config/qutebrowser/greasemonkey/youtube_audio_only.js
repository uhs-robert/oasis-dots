// qutebrowser/.config/qutebrowser/greasemonkey/youtube_audio_only.js
// ==UserScript==
// @name         YouTube Audio Only
// @namespace    http://tampermonkey.net/
// @version      4.1
// @description  Audio-only mode with UI alignment (bandwidth savings coming soon)
// @author       YourName
// @match        https://www.youtube.com/*
// @icon         https://www.youtube.com/favicon.ico
// @grant        unsafeWindow
// @grant        GM_addStyle
// @run-at       document-idle
// @updateURL    https://github.com/atishramkhe/Youtube-audio-only/raw/main/youtube_audio_only.user.js
// @downloadURL  https://github.com/atishramkhe/Youtube-audio-only/raw/main/youtube_audio_only.user.js
// ==/UserScript==

(function () {
  "use strict";

  // Add our styles with perfect alignment
  GM_addStyle(`
        #yt-true-audio-toggle {
            background: transparent !important;
            color: #f1f1f1 !important;
            border: none !important;
            padding: 0 10px !important; /* Adjust padding for better fit */
            margin: 0 !important;
            cursor: pointer !important;
            font-size: 14px !important;
            font-family: "Roboto","Arial",sans-serif !important;
            height: 36px !important; /* Match YouTube button height */
            line-height: 36px !important; /* Center text vertically */
            display: inline-flex !important;
            align-items: center !important;
            position: relative !important;
            vertical-align: middle !important; /* Align with other controls */
            opacity: 0.9;
            transition: opacity 0.2s;
        }
        #yt-true-audio-toggle:hover {
            opacity: 1;
            background: rgba(255,255,255,0.1) !important;
        }
        #yt-true-audio-toggle.audio-mode {
            color: #3ea6ff !important;
        }
        .yt-audio-only-wrapper {
            display: inline-block !important;
            height: 36px !important; /* Match wrapper height to button height */
            position: relative !important;
        }
    `);

  // State management
  let audioOnlyMode = false;
  let originalQuality = null;
  let currentVideoId = null;
  let videoObserver = null;

  // Create perfectly aligned toggle button
  function createToggleButton() {
    if (document.getElementById("yt-true-audio-toggle")) return;

    const controls = document.querySelector(".ytp-right-controls");
    if (!controls) return;

    const wrapper = document.createElement("div");
    wrapper.className = "yt-audio-only-wrapper";

    const toggle = document.createElement("button");
    toggle.id = "yt-true-audio-toggle";
    toggle.textContent = "Audio";
    toggle.title = "True audio-only mode (saves bandwidth)";
    toggle.addEventListener("click", toggleTrueAudioMode);

    wrapper.appendChild(toggle);

    // Insert after the cast button (or first if cast not found)
    const castButton = controls.querySelector(".ytp-cast-button");
    if (castButton) {
      castButton.parentNode.insertBefore(wrapper, castButton.nextSibling);
    } else {
      controls.insertBefore(wrapper, controls.firstChild);
    }

    // Add spacer for perfect alignment
    if (!controls.querySelector(".yt-audio-only-spacer")) {
      const spacer = document.createElement("div");
      spacer.className = "yt-audio-only-spacer";
      spacer.style.width = "8px";
      spacer.style.display = "inline-block";
      wrapper.parentNode.insertBefore(spacer, wrapper);
    }
  }

  // Toggle between modes
  function toggleTrueAudioMode() {
    audioOnlyMode = !audioOnlyMode;

    if (audioOnlyMode) {
      enableTrueAudioMode();
    } else {
      disableTrueAudioMode();
    }

    updateButtonState();
  }

  // Enable bandwidth-saving mode
  function enableTrueAudioMode() {
    const player = unsafeWindow.document.getElementById("movie_player");
    if (!player) return;

    // 1. Save original state
    originalQuality = player.getPlaybackQuality();
    currentVideoId = getCurrentVideoId();

    // 2. Force minimal video quality
    player.setPlaybackQuality("tiny");
    interceptQualityChanges(true);

    // 3. Reduce video processing
    const video = document.querySelector("video.html5-main-video");
    if (video) {
      video.style.opacity = "0";
      video.style.pointerEvents = "none";
      video.pause(); // Reduces processing
      setTimeout(() => video.play(), 50); // Audio continues
    }

    // 4. Monitor for video changes
    startVideoObserver();
  }

  // Disable audio-only mode
  function disableTrueAudioMode() {
    const player = unsafeWindow.document.getElementById("movie_player");
    if (player && originalQuality) {
      interceptQualityChanges(false);
      player.setPlaybackQuality(originalQuality);
    }

    const video = document.querySelector("video.html5-main-video");
    if (video) {
      video.style.opacity = "1";
      video.style.pointerEvents = "auto";
      video.play();
    }

    stopVideoObserver();
  }

  // Intercept quality changes
  function interceptQualityChanges(enable) {
    const player = unsafeWindow.document.getElementById("movie_player");
    if (!player) return;

    if (enable) {
      player._originalSetQuality = player.setPlaybackQuality;
      player.setPlaybackQuality = function () {
        return this._originalSetQuality("tiny");
      };
    } else if (player._originalSetQuality) {
      player.setPlaybackQuality = player._originalSetQuality;
    }
  }

  // Watch for video element changes
  function startVideoObserver() {
    stopVideoObserver();

    videoObserver = new MutationObserver((mutations) => {
      const video = document.querySelector("video.html5-main-video");
      if (video && audioOnlyMode) {
        video.style.opacity = "0";
        video.style.pointerEvents = "none";
      }

      // Check for video change
      const newVideoId = getCurrentVideoId();
      if (newVideoId && newVideoId !== currentVideoId) {
        currentVideoId = newVideoId;
        setTimeout(enableTrueAudioMode, 300);
      }
    });

    videoObserver.observe(document.body, {
      childList: true,
      subtree: true,
    });
  }

  function stopVideoObserver() {
    if (videoObserver) {
      videoObserver.disconnect();
      videoObserver = null;
    }
  }

  function updateButtonState() {
    const toggle = document.getElementById("yt-true-audio-toggle");
    if (toggle) {
      toggle.textContent = audioOnlyMode ? "Video" : "Audio";
      toggle.classList.toggle("audio-mode", audioOnlyMode);
    }
  }

  function getCurrentVideoId() {
    try {
      return (
        unsafeWindow.ytplayer?.config?.args?.video_id ||
        new URLSearchParams(window.location.search).get("v")
      );
    } catch (e) {
      return null;
    }
  }

  // Initialize
  function init() {
    createToggleButton();

    // Re-apply audio mode if active
    if (audioOnlyMode) {
      setTimeout(enableTrueAudioMode, 500);
    }
  }

  // Start when ready
  const readyStateCheck = setInterval(() => {
    if (document.querySelector(".ytp-right-controls")) {
      clearInterval(readyStateCheck);
      init();

      // Handle SPA navigation
      document.addEventListener("yt-navigate-finish", init);
    }
  }, 100);
})();
