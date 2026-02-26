// qutebrowser/.config/qutebrowser/greasemonkey/knack_show_ids.user.js
// ==UserScript==
// @name        Knack - Show IDs in Live App
// @namespace   Violentmonkey Scripts
// @match        *://*.knack.com/*
// @exclude      *://builder.knack.com/*
// @grant       none
// @require  https://ajax.googleapis.com/ajax/libs/jquery/1.7.2/jquery.min.js
// @version     1.0
// @author      Robert Hill
// @description 2/22/2024, 4:50:53 PM
// ==/UserScript==

/*
 * SETTINGS
 *
 */
if (!window.show_knack_id) {
  window.show_knack_id = {
    isEnabled: false,
    isNextGen: false,
    intervals: new Map(),
  };
}

/*
 * INTERVAL MANAGER
 *
 */
/**
 * Manages intervals by label for easy starting and stopping
 * @namespace
 * @property {Map} list - Map of interval labels to interval IDs
 * @property {Function} start - Starts or restarts an interval with a label
 * @property {Function} stop - Stops an interval by label
 */
const Intervals = {
  list: new Map(),
  start: (label, fn, ms) => {
    if (Intervals.list.has(label)) clearInterval(Intervals.list.get(label));
    const id = setInterval(fn, ms);
    Intervals.list.set(label, id);
    return id;
  },
  stop: (label) => {
    const id = Intervals.list.get(label);
    if (id) clearInterval(id);
    Intervals.list.delete(label);
  },
};

/*
 * UTLITIES
 *
 */

/**
 * Adds field IDs to elements matching the specified selector within a view.
 * @param {string} selector - CSS selector for target elements (e.g., 'th', '.kn-detail', '.kn-input')
 * @param {string} key - The view key identifier
 * @param {string} [type] - Optional type of the view (e.g., 'form')
 */
const addIdToFields = (selector, key, type) => {
  const targetElements = $(`#${key} ${selector}`);
  const processElement = (el) => {
    const hasId = !!el.querySelector(`.show-live-id`);
    if (hasId) return;
    const $el = $(el);
    const fieldName =
      type === "form"
        ? $el.data("input-id")
        : el.className.split(/\s+/).find((cn) => cn.startsWith("field_"));
    if (
      fieldName &&
      (!type || type !== "form" || fieldName.includes("field_"))
    ) {
      const $span = $("<span>")
        .addClass("show-live-id")
        .text(` ${fieldName}`)
        .css({
          color: "#ED7777",
          fontWeight: "bold",
          display: window.show_knack_id.isEnabled ? "inherit" : "none",
        });
      $el.append($span);
    }
  };
  targetElements.each(function () {
    processElement(this);
  });
};

/**
 * Polls until Knack is initialized and ready
 */
const waitTillKnackReady = () => {
  const resolve = () => {
    if (window.show_knack_id.isNextGen) {
      if (window.Knack?.ready) {
        Intervals.stop("isKnackReady");
        Knack.ready().then(async () => {
          addNextGenRenderEvents();
        });
      }
    } else {
      if (window.Knack?.initialized) {
        Intervals.stop("isKnackReady");
        addLegacyRenderEvents();
      }
    }
  };

  Intervals.start("isKnackReady", resolve, 1000);
};

/**
 * Adds a visual ID label to a Knack element (scene or view).
 * Creates a container div with the element's key that can be toggled on/off.
 * @param {string} key - The unique key identifier for the scene or view
 * @param {Object} obj - The scene or view object data to be logged on double-click
 */
const addIdToElement = (key, obj) => {
  const { isNextGen, isEnabled } = window.show_knack_id;
  const isScene = key.includes("scene");
  const targetID = !isNextGen && isScene ? `kn-${key}` : key;
  const scriptId = `userscript-${key}`;

  // Create the container div with its properties and styling
  const getContainer = () => {
    return $("<div>", {
      id: scriptId,
      class: `show-live-id show-${isScene ? "scene" : "view"}-id`,
      css: {
        "margin-bottom": !isNextGen && isScene ? "2em" : "",
        display: isEnabled ? "inherit" : "none",
      },
      dblclick: () => console.log(obj), // Log the object on double-click
    }).data("obj", obj);
  };

  /**
   * Creates a styled span element for displaying the key
   * @returns {jQuery} jQuery-wrapped span element
   */
  const getSpan = () => {
    return $("<span>", {
      text: key,
      css: {
        color: "#D06666",
        fontSize: "1em",
        fontWeight: "bold",
      },
    });
  };

  // Early exit
  const scriptEl = $(`#${scriptId}`);
  const isAdded = scriptEl.length;
  if (!isNextGen && isAdded) return;

  // Create container
  const container = getContainer();
  const span = getSpan();
  span.appendTo(container);
  scriptEl?.remove();

  // Handle next gen
  if (isNextGen) {
    if (isScene) {
      $(".show-scene-id").remove();
    }
  }

  // Add container
  $(`#${targetID}`).prepend(container);
};

/**
 * Sets up render event handlers for next-generation Knack apps (apps.knack.com).
 * Currently a placeholder for future implementation.
 */
const addNextGenRenderEvents = () => {
  window.show_knack_id.curr_scene = [];

  /**
   * Adds ID labels to scene elements
   * @param {Object} scene - Scene object from Knack
   */
  const addToPages = async (key) => {
    const { isEnabled } = window.show_knack_id;
    const page = await Knack.getPage(key);
    const { authenticated, authentication_profiles, modal, name } = page;

    window.show_knack_id.curr_scene.push({
      [key]: key,
      name,
      modal,
      authentication_profiles,
    });
    addIdToElement(key, { key, page });
    const currScene = [...window.show_knack_id.curr_scene];
    if (isEnabled)
      console.debug({ [key]: currScene, name, modal, authenticated });
    window.show_knack_id.curr_scene.length = 0;
  };

  /**
   * Adds ID labels to view elements then each field
   * @param {Object} key - View key
   * @param {Object} pageKey - Page key
   */
  const addToViews = async (key, pageKey) => {
    const view = await Knack.getView(key, pageKey);

    const { title, name, type } = view;
    window.show_knack_id.curr_scene.push({ [key]: view, type, name, title });
    const obj = {
      key,
      type,
      // recordId: data?.id,
      object: view.source?.object,
      view,
      // model: window.Knack?.models[key],
      // data,
    };
    addIdToElement(key, obj);
    // addToFields(view);
  };

  /**
   * Adds ID labels to field elements based on view type
   * @param {Object} view - View object from Knack
   */
  const addToFields = (view) => {
    switch (view.type) {
      case "table":
      case "search":
        addIdToFields("th", view.key);
        break;
      case "details":
      case "list":
        addIdToFields(".kn-detail", view.key);
        break;
      case "form":
        addIdToFields(".kn-input", view.key, view.type);
        break;
    }
  };

  // SCENE RENDER
  Knack.on("page:render", (page) => {
    // console.debug({ page });
    addToPages(page.pageKey);
  });

  // VIEW RENDER
  Knack.on("view:render", async (view) => {
    // console.debug({ view });
    addToViews(view.viewKey, view.pageKey);
  });

  // Toggle IDs
  $("#showIDsCheckbox").on("change", function (_e) {
    const isChecked = $(this).is(":checked");
    if (isChecked) {
      window.show_knack_id.isEnabled = true;
      $(".show-live-id").show();
    } else {
      window.show_knack_id.isEnabled = false;
      $(".show-live-id").hide();
    }
  });
};

/**
 * Sets up render event handlers for legacy Knack apps.
 * Listens for scene and view render events and adds ID labels to elements.
 * Includes handlers for tables, details, lists, forms, and a toggle checkbox.
 */
const addLegacyRenderEvents = () => {
  window.show_knack_id.curr_scene = [];

  /**
   * Adds ID labels to scene elements
   * @param {Object} scene - Scene object from Knack
   */
  const addToScenes = (scene) => {
    const { isEnabled } = window.show_knack_id;
    const { key, authenticated, authentication_profiles, modal, name } = scene;
    window.show_knack_id.curr_scene.push({
      [key]: scene,
      name,
      modal,
      authentication_profiles,
    });
    addIdToElement(scene.key, { key: scene.key, scene });
    const currScene = [...window.show_knack_id.curr_scene];
    if (isEnabled)
      console.debug({ [scene.key]: currScene, name, modal, authenticated });
    window.show_knack_id.curr_scene.length = 0;
  };

  /**
   * Adds ID labels to view elements
   * @param {Object} view - View object from Knack
   * @param {Object} data - Data associated with the view render
   */
  const addToViews = (view, data) => {
    const { title, name, key, type } = view;
    window.show_knack_id.curr_scene.push({ [key]: view, type, name, title });
    const obj = {
      key,
      type,
      recordId: data?.id,
      object: view.source?.object,
      view,
      model: window.Knack?.models[key],
      data,
    };
    addIdToElement(key, obj);
  };

  /**
   * Adds ID labels to field elements based on view type
   * @param {Object} view - View object from Knack
   */
  const addToFields = (view) => {
    switch (view.type) {
      case "table":
      case "search":
        addIdToFields("th", view.key);
        break;
      case "details":
      case "list":
        addIdToFields(".kn-detail", view.key);
        break;
      case "form":
        addIdToFields(".kn-input", view.key, view.type);
        break;
    }
  };

  // SCENE RENDER
  $(document).on("knack-scene-render.any", (_e, scene) => {
    addToScenes(scene);
  });
  // VIEW RENDER
  $(document).on("knack-view-render.any", (_e, view, data) => {
    addToViews(view, data);
    addToFields(view);
  });

  // Toggle IDs
  $("#showIDsCheckbox").on("change", function (_e) {
    const isChecked = $(this).is(":checked");
    if (isChecked) {
      window.show_knack_id.isEnabled = true;
      $(".show-live-id").show();
    } else {
      window.show_knack_id.isEnabled = false;
      $(".show-live-id").hide();
    }
  });
};

/**
 * Main entry point for the userscript
 * Detects whether the app is next-gen or legacy and initializes the appropriate event handlers
 */
const main = () => {
  const isNextGen = window.location.hostname.split(".")[0] === "apps";
  window.show_knack_id.isNextGen = isNextGen;
  if (isNextGen) window.show_knack_id.isEnabled = true;
  waitTillKnackReady();
};

main();
