// qutebrowser/.config/qutebrowser/greasemonkey/knack_search.user.js
// ==UserScript==
// @name        Knack Live - Search Builder
// @namespace   Violentmonkey Scripts
// @match        *://*.knack.com/*
// @exclude      *://builder.knack.com/*
// @grant       none
// @version     1.0
// @author      Robert Hill
// @description 2/22/2024, 4:50:53 PM
// ==/UserScript==
const htmlFilterGroup = `
<header class="modal-card-head">
  <h1 class="modal-card-title">Add Filters</h1>
  <button class="delete close-modal"></button>
</header>

<section class="modal-card-body">
  <div id="kn-filters-form" class="kn-modal-wrapper kn-view kn-scene">
    <div class="filters-type" style="display: flex;">
      <label class="label kn-match-select" style="align-self: center;">Filter</label>
      <span class="type kn-select" style="width: 25%;">
        <select class="type select" name="type">
          <option value="scene">Scenes</option>
          <option value="view">Views</option>
          <option value="object">Objects</option>
          <option value="field">Fields</option>
        </select>
      </span>
    </div>

    <ul class="filters-list" style="list-style: none;">
      <li class="kn-filter-match" style="display: flex; flex-direction: row; align-items: center; flex-wrap: nowrap; padding: 5px; margin-top: 0.25em;">
        <span class="label kn-match-select" style="align-self: center;">That match</span>
        <span class="match kn-select kn-match-select">
          <select class="match" name="match">
            <option value="and">all</option>
            <option value="or">any</option>
          </select>
        </span>
        <span class="kn-match-select"> of these filters</span>
        <a class="kn-button add-filter-group" style="margin-left: auto;">
          <span class="icon is-small">
            <i class="fa fa-plus-circle"></i>
          </span>
          <span>Add group</span>
        </a>
      </li>
      <li class="kn-filter-item">
        <label class="label kn-match-select">where</label>
        <span class="match kn-select kn-match-select" style="display: none;">
          <select class="match" name="match">
            <option value="and">and</option>
            <option value="or">or</option>
          </select>
        </span>

        <span class="property kn-select">
          <select class="property select" name="property">
            <option value="key">ID</option>
          </select>
        </span>

        <span class="operator kn-select">
          <select class="operator select" name="operator">
            <option value="is">is</option>
          </select>
        </span>
        <span class="kn-filter-value kn-select value">
          <input class="input" name="value" type="text">
        </span>
        <a class="remove-filter-link kn-filter-remove" title="Remove this filter">
          <span class="icon is-small">
            <i class="fa fa-minus-circle"></i>
          </span>
          <span class="kn-remove-filter-text">Remove</span>
        </a>
      </li>
      <li class="add-filter">
        <a class="kn-button add-filter-link" style="margin-top: 1em;">
          <span class="icon is-small">
            <i class="fa fa-plus-circle"></i>
          </span>
          <span>Add filter</span>
        </a>
      </li>
    </ul>
  </div>
</section>

<footer class="modal-card-foot is-centered">
  <input id="kn-submit-filters" type="submit" class="kn-button is-primary is-medium" value="Submit">
</footer>`;

const generateResults = (type, resultsCount = 0) => {
  let results = "";
  switch (type) {
    case "filter":
      results = `Search Results Found:
            <span class="results-value" style="color: red;">${resultsCount}</span>
            <br />
            <span style='font-size: smaller;'><em>(Refer to console.log for details)</em></span>`;
      break;
    case "export":
      results = `<span>CSV Generated, please check your downloads folder to view the results.</span>`;
      break;
    default:
      return;
  }

  return `
    <section class="modal-card-results is-centered" style="
      background-color: hsl(0, 0%, 100%);
      border-radius: 0.35em;
      margin-bottom: 4em;
      margin-top: -2em;
      justify-content: center;
      text-align: center;">
      <hr>
      <div id="modal-results">${results}</div>
    </section>`;
};

const htmlExport = `
<header class="modal-card-head">
  <h1 class="modal-card-title">Export Knack Data to CSV</h1>
  <button class="delete close-modal"></button>
</header>

<section class="modal-card-body">
  <div id="kn-export-form" class="kn-modal-wrapper kn-view kn-scene">
    <div class="export-type" style="display: flex;">
      <label class="label kn-match-select" style="align-self: center; margin-right: 1em;">Select Data to Export</label>
      <span class="type kn-select" style="width: 50%;">
        <select class="type select" name="type">
          <option value="scene">Scenes</option>
          <option value="view">Views</option>
          <option value="object">Objects</option>
          <option value="field">Fields</option>
          <option value="email">Emails</option>
          <option value="record-rule">Record Rules</option>
        </select>
      </span>
      <span>
      </span>
  </div>
</section>

<footer class="modal-card-foot is-centered">
  <input id="kn-submit-export" type="submit" class="kn-button is-primary is-medium" value="Submit">
</footer>
`;

const operators = {
  is: (prop, value) =>
    String(prop).toLowerCase() === String(value).toLowerCase(),
  "is not": (prop, value) =>
    String(prop).toLowerCase() !== String(value).toLowerCase(),
  contains: (prop, value) =>
    Array.isArray(prop)
      ? prop.includes(value)
      : prop
        ? prop.toLowerCase().includes(value.toLowerCase())
        : false,
  "does not contain": (prop, value) =>
    Array.isArray(prop)
      ? !prop.includes(value)
      : prop
        ? !prop.toLowerCase().includes(value.toLowerCase())
        : true,
  "starts with": (prop, value) =>
    prop !== undefined &&
    prop !== null &&
    prop.toLowerCase().startsWith(value.toLowerCase()),
  "ends with": (prop, value) =>
    prop !== undefined &&
    prop !== null &&
    prop.toLowerCase().endsWith(value.toLowerCase()),
  "is blank": (prop) => prop === "" || prop === undefined || prop === null,
  "is not blank": (prop) => prop !== "" && prop !== undefined && prop !== null,
  exists: (prop) =>
    Array.isArray(prop) ? prop.length > 0 : prop !== null && prop !== undefined,
  "does not exist": (prop) =>
    Array.isArray(prop)
      ? prop.length === 0
      : prop === null || prop === undefined,
  "is any": (prop) => !!prop,
  has: (prop) =>
    Array.isArray(prop)
      ? prop.length > 0
      : prop !== null && prop !== undefined && prop !== "",
  "does not have": (prop) =>
    Array.isArray(prop)
      ? prop.length === 0
      : prop === null || prop === undefined || prop === "",
};

const filterKnackModels = (type = "view", filters = [], getKeyOnly = true) => {
  /*
	const filters = [
	{
		match: "and",
		rules: [
		{
			property: 'title',
			operator: 'contains',
			value: 'Business'
		},
		{
			property: 'type',
			operator: 'is',
			value: 'details'
		}
		]
	},
	// Additional groups with "or" or more "and" conditions could follow
	];
	*/
  function getValueByPath(obj, path) {
    // Handles both dot notation and array access notation
    return path
      .replace(/\[(\w+)\]/g, ".$1") // Convert indices to properties
      .split(".") // Split by dot to get individual properties
      .reduce((acc, part) => acc && acc[part], obj); // Navigate through the object
  }

  // Determine models based on type
  type = type.toLowerCase();
  let models =
    type === "scene"
      ? Knack.scenes.models
      : type === "view"
        ? Knack.scenes.models.flatMap((scene) => scene.views.models)
        : type === "object"
          ? Knack.objects.models
          : type === "field"
            ? Knack.objects.models.flatMap((object) => object.fields.models)
            : [];

  // Return all models' keys if no filters are provided
  if (!filters || filters.length === 0) {
    return models.map((item) =>
      getKeyOnly ? item.key : item.attributes || item,
    );
  }

  // Filter application
  return models.flatMap((item) => {
    const target = item.attributes || item;
    const meetsCriteria = filters.every((group) => {
      if (!group.match || group.match === "and") {
        const rules = group.rules || [group];
        return rules.every(({ property, operator, value }) =>
          operators[operator](getValueByPath(target, property), value),
        );
      } else if (group.match === "or") {
        return group.rules.some(({ property, operator, value }) =>
          operators[operator](getValueByPath(target, property), value),
        );
      }
    });
    return meetsCriteria ? [getKeyOnly ? item.key : target] : [];
  });
};

const operatorMap = {
  boolean: [
    { value: "is", text: "is" },
    { value: "is not", text: "is not" },
    { value: "exists", text: "exists" },
    { value: "does not exist", text: "does not exist" },
  ],
  arrayBoolean: [
    { value: "exists", text: "exists" },
    { value: "does not exist", text: "does not exist" },
  ],
  array: [
    { value: "exists", text: "exists" },
    { value: "does not exist", text: "does not exist" },
    { value: "contains", text: "contains" },
    { value: "does not contain", text: "does not contain" },
    { value: "is", text: "is" },
    { value: "is not", text: "is not" },
  ],
  select: [
    { value: "is", text: "is" },
    { value: "is not", text: "is not" },
    { value: "is any", text: "is any" },
    { value: "is blank", text: "is blank" },
    { value: "is not blank", text: "is not blank" },
  ],
  object: [
    { value: "has", text: "has" },
    { value: "does not have", text: "does not have" },
  ],
  text: [
    { value: "contains", text: "contains" },
    { value: "does not contain", text: "does not contain" },
    { value: "is", text: "is" },
    { value: "is not", text: "is not" },
    { value: "starts with", text: "starts with" },
    { value: "ends with", text: "ends with" },
    { value: "is blank", text: "is blank" },
    { value: "is not blank", text: "is not blank" },
  ],
};

const createSearchElements = (handleSearchFunction, width = "15em") => {
  // Add CSS to document head
  const css = `.show-hidden { display: block !important; }`;
  const style = document.createElement("style");
  document.head.appendChild(style);
  style.type = "text/css";
  style.appendChild(document.createTextNode(css));

  // Main container for the search elements
  const searchContainer = document.createElement("div");
  searchContainer.className = "level-right";
  searchContainer.style = "margin-left: auto;";
  searchContainer.id = "builder-search-container";

  // Builder search container to hold input and buttons
  const builderSearchContainer = document.createElement("div");
  builderSearchContainer.id = "builder-search";
  builderSearchContainer.style =
    "display: none; flex-direction: row; align-items: normal;";

  // Search bar input
  const searchInput = document.createElement("input");
  searchInput.type = "text";
  searchInput.placeholder = "Search Views...";
  searchInput.className = "search-bar";
  searchInput.setAttribute("data-type", "view");
  searchInput.style = `width: ${width}; border-radius: 4px 0 0 4px; border: 1px solid rgb(204, 204, 204); border-right: none;`;

  // Menu button with three vertical dots
  const menuButton = document.createElement("button");
  menuButton.innerHTML = "&#8942;"; // HTML entity for three vertical dots
  menuButton.className = "menu-button";
  menuButton.style =
    "border: 1px solid rgb(204, 204, 204); border-left: none; background: none; cursor: pointer; padding: 5px;";

  // Search button
  const searchButton = document.createElement("button");
  searchButton.innerHTML = "Search";
  searchButton.className = "search-button";
  searchButton.style =
    "border-top: 1px solid rgb(204, 204, 204); border-right: 1px solid rgb(204, 204, 204); border-bottom: 1px solid rgb(204, 204, 204); border-left: none; background-color: #3DB5FF; color: white; cursor: pointer; padding: 5px; border-radius: 0 4px 4px 0;";

  // Popup menu for search mode selection
  const popupMenu = document.createElement("div");
  popupMenu.style =
    "display: none; position: absolute; background-color: rgb(255, 255, 255); border: 1px solid rgb(204, 204, 204); border-radius: 4px; padding: 5px; text-align: left; right: 82px; margin-top: 6px;";

  // Add popup options
  const createOption = ({
    text,
    searchPlaceholder,
    type = false,
    onClick = true,
  }) => {
    const option = document.createElement("div");
    option.textContent = text;
    option.style = "padding: 5px; cursor: pointer;";
    if (onClick) {
      option.onclick = () => {
        searchInput.placeholder = searchPlaceholder;
        if (type !== false) searchInput.dataset.type = type;
        popupMenu.style.display = "none";
      };
    }
    popupMenu.appendChild(option);
    return option;
  };
  const createSeperator = () => {
    const separator = document.createElement("hr");
    separator.style.margin = "10px 0";
    return separator;
  };
  const createCheckBox = ({ text, id, name, isChecked = false }) => {
    // Container div
    const div = document.createElement("div");
    div.style.cssText = "padding: 5px; display: flex; align-items: center;";
    // Checkbox input
    const input = document.createElement("input");
    input.type = "checkbox";
    input.id = id;
    input.name = name ? name : id;
    input.checked = isChecked;
    input.style.marginRight = "5px";
    // Label
    const label = document.createElement("label");
    label.htmlFor = id;
    label.textContent = text;
    div.appendChild(input);
    div.appendChild(label);
    popupMenu.appendChild(div);
    return input;
  };
  const scenesOption = createOption({
    text: "Scenes",
    searchPlaceholder: "Search Scenes...",
    type: "scene",
  });
  const viewsOption = createOption({
    text: "Views",
    searchPlaceholder: "Search Views...",
    type: "view",
  });
  const objectsOption = createOption({
    text: "Objects",
    searchPlaceholder: "Search Objects...",
    type: "object",
  });
  const fieldsOption = createOption({
    text: "Fields",
    searchPlaceholder: "Search Fields...",
    type: "field",
  });
  const filterOption = createOption({
    text: "Advanced Filter",
    searchPlaceholder: "Refer to Filter...",
    type: "filter",
  });

  // Add Export to CSV Button
  popupMenu.appendChild(createSeperator());
  const csvExportOption = createOption({
    text: "Export Knack Data to CSV",
    onCLick: false,
  });
  csvExportOption.onclick = () => {
    Knack.renderModal(htmlExport);
    $("#kn-submit-export").on("click", function (e) {
      $("#kn-filters-form .filters-type .type select").val();
      const selection = $("#kn-export-form select").val();
      getKnackDataCsv({ type: selection, autoDownload: true });

      const $modal = $("#kn-modal-bg-0");
      let $results = $modal.find("#modal-results");
      if (!$results || $results.length === 0) {
        $results = $(generateResults("export")).hide();
        $modal.find("footer").before($results);
      }
      $results.fadeIn(500);
    });
  };

  // Add Show ID Checkbox
  popupMenu.appendChild(createSeperator());
  createCheckBox({
    text: "Show IDs in Live App",
    id: "showIDsCheckbox",
    name: "showIDs",
    isChecked: false,
  });

  // Add show ALL hidden elements checkbox
  const showAllHidden = createCheckBox({
    text: "Show Hidden Elements",
    id: "showAllHidden",
    name: "showAllHidden",
    isChecked: false,
  });
  showAllHidden.onclick = () => {
    const allElements = document.querySelectorAll("*"); // Select all elements
    const excludeClasses = ["overlay"]; // Add more class names as needed
    const excludeTags = ["HEAD", "SCRIPT", "STYLE"]; // Add more tag names as needed
    const excludeIds = ["kn-loading-spinner", "fancybox-loading", "kn-popover"]; // Add more IDs as needed

    const hiddenElements = Array.from(allElements).filter((el) => {
      const hasExcludedClass = excludeClasses.some((className) =>
        el.classList.contains(className),
      );
      const hasExcludedTag = excludeTags.includes(el.tagName);
      const hasExcludedId =
        excludeIds.includes(el.id) || el.id.includes("fancybox");
      return (
        !hasExcludedClass &&
        !hasExcludedId &&
        !hasExcludedTag &&
        (window.getComputedStyle(el).display === "none" ||
          el.classList.contains("show-hidden"))
      );
    });
    const showHidden = showAllHidden.checked;
    hiddenElements.forEach((el) => {
      showHidden
        ? el.classList.add("show-hidden")
        : el.classList.remove("show-hidden");
    });
  };

  filterOption.onclick = () => {
    popupMenu.style.display = "none";
    Knack.renderModal(htmlFilterGroup);
    // Initialize filterOptions with default values
    let filterOptions = [];

    // Event for Filter Type: Change
    $("#kn-filters-form .filters-type .type select").on("change", function () {
      const selectedValue = $(this).val();
      filterOptions = [
        { value: "key", text: `ID`, type: "select" },
        { value: "name", text: "Name", type: "text" },
      ];
      switch (selectedValue) {
        case "scene":
          filterOptions.push(
            { value: "print", text: "Can Print?", type: "boolean" },
            { value: "modal", text: "Is Modal?", type: "boolean" },
            {
              value: "authenticated",
              text: "Login Required?",
              type: "boolean",
            },
            {
              value: "authentication_profiles",
              text: "Login Profiles",
              type: "array",
            },
            { value: "object", text: "Object", type: "select" },
            {
              value: "page_menu_display",
              text: "Page Menu is Displayed",
              type: "boolean",
            },
            { value: "slug", text: "Slug for URL", type: "text" },
          );
          break;
        case "view":
          filterOptions.push(
            { value: "description", text: "Description", type: "text" },
            { value: "label", text: "Label", type: "text" },
            {
              value: "action",
              text: "Form Action",
              type: "select",
              options: [
                { value: "create", text: "Create New Record" },
                { value: "insert", text: "Insert Connected Record" },
                { value: "update", text: "Update Existing Record" },
              ],
            },
            { value: "source.object", text: "Object ID", type: "select" },
            {
              value: "rules",
              text: "Rules",
              type: "object",
              options: [
                { value: "rules.emails", text: "Email Rules" },
                { value: "rules.fields", text: "Display Rules" },
                { value: "rules.records", text: "Record Rules" },
                { value: "rules.submits", text: "Submit Rules" },
              ],
            },
            { value: "scene.key", text: "Scene ID", type: "select" },
            { value: "title", text: "Title", type: "text" },
            {
              value: "type",
              text: "Type",
              type: "select",
              options: [
                { value: "calendar", text: "Calendar" },
                { value: "details", text: "Details" },
                { value: "form", text: "Form" },
                { value: "list", text: "List" },
                { value: "menu", text: "Menu" },
                { value: "search", text: "Search" },
                { value: "table", text: "Table" },
              ],
            },
          );
          break;
        case "object":
          filterOptions.push(
            { value: "conns", text: "Connections?", type: "arrayBoolean" },
            { value: "user", text: "Is User?", type: "boolean" },
          );
          break;
        case "field":
          filterOptions.push(
            {
              value: "validation",
              text: "Data Validation",
              type: "arrayBoolean",
            },
            { value: "conditional", text: "Is Conditional?", type: "boolean" },
            { value: "required", text: "Is Required?", type: "boolean" },
            { value: "unique", text: "Is Unique?", type: "boolean" },
            { value: "user", text: "Is User?", type: "boolean" },
            { value: "object_key", text: "Object ID", type: "select" },
            {
              value: "type",
              text: "Type",
              type: "select",
              options: [
                { value: "short_text", text: "Short Text" },
                { value: "paragraph_text", text: "Paragraph Text" },
                { value: "rich_text", text: "Rich Text" },
                { value: "concatenation", text: "Text Formula" },
                { value: "number", text: "Number" },
                { value: "currency", text: "Currency" },
                { value: "equation", text: "Equation" },
                { value: "auto_increment", text: "Auto Increment" },
                { value: "sum", text: "Sum" },
                { value: "min", text: "Min" },
                { value: "max", text: "Max" },
                { value: "average", text: "Average" },
                { value: "count", text: "Count" },
                { value: "multiple_choice", text: "Multiple Choice" },
                { value: "boolean", text: "Yes/No" },
                { value: "date_time", text: "Date Time" },
                { value: "timer", text: "Timer" },
                { value: "file", text: "File" },
                { value: "image", text: "Image" },
                { value: "name", text: "Person" },
                { value: "email", text: "Email" },
                { value: "address", text: "Address" },
                { value: "phone", text: "Phone" },
                { value: "link", text: "Link" },
                { value: "signature", text: "Signature" },
                { value: "rating", text: "Rating" },
                { value: "connection", text: "Connection" },
              ],
            },
          );
          break;
        default:
          break;
      }

      // Remove extra filter groups and existing options from the second select (the dynamic 'property' select)
      $("#kn-filters-form .filters-list:not(:first)").remove();
      const $propertySelect = $(
        "#kn-filters-form ul.filters-list .property select",
      ).empty();

      // Append the new options to the 'property' select
      filterOptions.forEach((option) => {
        $propertySelect.append(
          $("<option>", { value: option.value, text: option.text }),
        );
      });
      $(
        "#kn-filters-form ul.filters-list li.kn-filter-item:not(:last)",
      ).remove();
      $propertySelect.val("key").trigger("change");
    });

    // Event for Filter Operator: Change
    $("#kn-filters-form").on(
      "change",
      ".filters-list .operator select",
      function () {
        const selectedOption = $(this).val();
        const $filterValue = $(this).closest("li").find(".kn-filter-value");
        const hideValueField = [
          "exists",
          "does not exist",
          "is any",
          "is blank",
          "is not blank",
        ].includes(selectedOption);
        hideValueField ? $filterValue.hide() : $filterValue.show();
      },
    );

    // Event for Filter Property: Change
    $("#kn-filters-form").on(
      "change",
      ".filters-list .property select",
      function () {
        const selectedOption = filterOptions.find(
          (option) => option.value === $(this).val(),
        );
        const $li = $(this).closest("li");
        const $filterValueContainer = $li.find(".kn-filter-value");
        const $operatorContainer = $li.find(".operator");
        $filterValueContainer.empty();
        $operatorContainer.empty();

        // Decide the operators
        const operatorSelect = $("<select>", {
          class: "select",
          name: "operator",
        });
        const operatorOptions = operatorMap[selectedOption.type];
        operatorOptions.forEach((opt) =>
          operatorSelect.append($("<option>", opt)),
        );
        $operatorContainer.append(operatorSelect);

        // Decide the value field
        switch (selectedOption.type) {
          case "boolean":
          case "arrayBoolean":
            const booleanSelect = $("<select>", {
              class: "select",
              name: "value",
              "data-type": selectedOption.type,
            })
              .append($("<option>", { value: "true", text: "True" }))
              .append($("<option>", { value: "false", text: "False" }));
            $filterValueContainer.append(booleanSelect);
            break;
          case "array":
          case "text":
            const textInput = $("<input>", {
              class: "input",
              type: "text",
              name: "value",
              "data-type": selectedOption.type,
            });
            $filterValueContainer.append(textInput);
            break;
          case "select":
          case "object":
            // Create a select with custom options
            const customSelect = $("<select>", {
              class: "select",
              name: "value",
              "data-type": selectedOption.type,
            });
            if (selectedOption.options) {
              selectedOption.options.forEach((option) => {
                customSelect.append(
                  $("<option>", { value: option.value, text: option.text }),
                );
              });
              $filterValueContainer.append(customSelect);
            } else {
              const textInput = $("<input>", {
                class: "input",
                type: "text",
                name: "value",
                "data-type": selectedOption.type,
              });
              $filterValueContainer.append(textInput);
            }
            break;
        }
        $operatorContainer.find("select").trigger("change");
      },
    );

    // Add new filter event
    $("#kn-filters-form").on("click", ".add-filter-link", function () {
      const $newFilterItem = $(".filters-list .kn-filter-item:last").clone();

      // Optionally reset the property select to its default value
      $newFilterItem.find(".property select").val(function () {
        return $(this).find("option:first").val();
      });

      // Reset input values within the cloned item
      $newFilterItem.find("input").val("");

      // Add the cloned item before the filter button
      $(this).before($newFilterItem);

      // Now, trigger the change event on the property select to update operator and value selects accordingly
      $newFilterItem.find(".property select").trigger("change");
    });

    // Add new filter group event
    $("#kn-filters-form").on("click", ".add-filter-group", function () {
      const $remove = $(`
        <a class="remove-group-link kn-filter-remove" title="Remove this group">
          <span class="icon is-small">
            <i class="fa fa-minus-circle"></i>
          </span>
          <span class="kn-remove-filter-text">Remove</span>
        </a>`);
      const matchSetting =
        $(".filters-list:first select.match").val() === "and" ? "or" : "and";
      const $lastGroup = $(".filters-list:last");
      const $newGroup = $lastGroup.clone();
      $newGroup.find("select.match").val(matchSetting).attr("disabled", true);
      $newGroup.find(".kn-filter-match span.label").text("And match");
      $newGroup.find(".remove-group-link")?.remove();
      $newGroup.find("hr")?.remove();
      $newGroup.prepend($("<hr>"));
      $remove.on("click", () => $newGroup.remove());

      // Remove all filter items except last
      $newGroup.find(".kn-filter-item:not(:last)").remove();

      // Reset the property select to its default value
      $newGroup.find(".property select").val(function () {
        return $(this).find("option:first").val();
      });

      // Reset input values within the cloned item
      $newGroup.find("input").val("");

      // Add the cloned item after the last group with remove button
      $newGroup.find(".add-filter-group").after($remove);
      $lastGroup.after($newGroup);

      // Now, trigger the change event on the property select to update operator and value selects accordingly
      $newGroup.find(".property select").trigger("change");
    });

    // Filter match ('all'/'any') change event
    $("#kn-filters-form").on("change", "select.match:first", function () {
      const value = $(this).val();
      const opposite = value === "and" ? "or" : "and";
      $("#kn-filters-form select.match:not(:first)").val(opposite);
    });

    // Remove filter item event
    $("#kn-filters-form").on("click", ".remove-filter-link", function (e) {
      const $filtersList = $(".filters-list");
      const $filterItems = $filtersList.find(".kn-filter-item");

      // Only remove if more than one filter item exists
      if ($filterItems.length > 1) {
        $(this).closest(".kn-filter-item").remove();
      }
    });

    // Conduct Search
    $("#kn-submit-filters").on("click", function (e) {
      const searchType = $("#kn-filters-form .filters-type .type select").val();
      const filters = [];
      // Extract the property, operator, and value from each filter group and item
      $("#kn-filters-form .filters-list").each(function () {
        const match = $(this).find("select.match").val() || "and";
        const filterGroup = {
          match,
          rules: [],
        };
        $(this)
          .find(".kn-filter-item")
          .each(function () {
            const $item = $(this);
            const $property = $item.find(".property select");
            const $operator = $item.find(".operator select");
            const $value = $item.find(
              ".kn-filter-value input, .kn-filter-value select",
            );
            const property =
              $value.data("type") === "object" ? $value.val() : $property.val();
            const operator = $operator.val();
            const value = $value.val();
            filterGroup.rules.push({ property, operator, value });
          });

        filters.push(filterGroup);
      });
      console.log(filters);
      // Get results and show results
      const matches = filterKnackModels(searchType, filters, false) || [];
      const resultsCount = matches ? matches.length : 0;
      const $modal = $("#kn-modal-bg-0");
      let $results = $modal.find("#modal-results");
      if (!$results || $results.length === 0) {
        $modal
          .find("footer")
          .before(generateResults("filter", resultsCount))
          .hide();
        $results = $modal.find("#modal-results");
      }
      $results.find(".results-value").text(resultsCount);
      $results.fadeIn(500);
      console.log({ searchType, matches });
    });

    // Set default filter options
    const $typeSelect = $("#kn-filters-form .filters-type .type select");
    const $propertySelect = $(
      "#kn-filters-form .filters-list .property select",
    );
    const searchType = searchInput.dataset.type;
    $typeSelect.val(searchType).trigger("change");
    $propertySelect.val("key").trigger("change");
  };

  // Toggle popup menu display
  menuButton.onclick = () => {
    popupMenu.style.display =
      popupMenu.style.display === "none" ? "block" : "none";
  };

  // Close popup menu on outside click
  document.addEventListener("click", (event) => {
    if (!searchContainer.contains(event.target)) {
      popupMenu.style.display = "none";
    }
  });

  // Prevent popup menu from closing when clicking inside
  popupMenu.addEventListener("click", (event) => {
    event.stopPropagation();
  });

  // Event handling for search functionality
  searchButton.addEventListener("click", handleSearchFunction);
  searchInput.addEventListener("keypress", (event) => {
    if (event.key === "Enter") handleSearchFunction();
  });

  // Create toggle button
  const toggleButton = document.createElement("button");
  toggleButton.className = "toggle-button"; // Assign a class for styling or targeting
  toggleButton.style.cssText =
    "cursor: pointer; background-color: transparent; border: none; font-size: 16px; align-self: baseline; color: #3DB5FF;";
  toggleButton.title = "Collapse search";
  const icon = document.createElement("i");
  icon.className = "fa fa-plus-square-o"; // Initial icon indicating it can be minimized
  toggleButton.appendChild(icon);
  // Event listener to toggle the visibility of the search bar
  toggleButton.addEventListener("click", function () {
    const isMaximized = icon.classList.contains("fa-minus-square-o");
    if (isMaximized) {
      builderSearchContainer.style.display = "none"; // Hide the search elements
      icon.className = "fa fa-plus-square-o"; // Change the icon to indicate it can be maximized
      //searchContainer.style.margin = '0';
      popupMenu.style.display = "none";
      toggleButton.title = "Expand search";
    } else {
      builderSearchContainer.style.display = "flex"; // Show the search elements
      icon.className = "fa fa-minus-square-o"; // Change the icon to indicate it can be minimized
      //searchContainer.style.margin = '1em';
      toggleButton.title = "Collapse search";
    }
  });

  // Append elements to the builder search container
  builderSearchContainer.appendChild(searchInput);
  builderSearchContainer.appendChild(menuButton);
  menuButton.appendChild(popupMenu);
  builderSearchContainer.appendChild(searchButton);

  // Append the builder search container and the popup menu to the main container
  searchContainer.appendChild(builderSearchContainer);
  //searchContainer.appendChild(popupMenu);
  searchContainer.appendChild(toggleButton);

  // Highlight and active state for popup menu options
  [
    scenesOption,
    viewsOption,
    objectsOption,
    fieldsOption,
    filterOption,
    csvExportOption,
  ].forEach((option) => {
    option.onmouseenter = () => (option.style.backgroundColor = "lightgrey");
    option.onmouseleave = () => (option.style.backgroundColor = "");
  });

  return { searchContainer, searchInput, searchButton, menuButton, popupMenu };
};

const addSearchBar = (elQuery) => {
  const navigateToBuilder = (type, obj) => {
    const getSubdomainAndPathName = () => {
      const subdomain = window.location.hostname.split(".")[0];
      const appname =
        Knack?.app?.attributes?.slug || window.location.pathname.split("/")[2];
      return { subdomain, appname };
    };
    const knackApp = getSubdomainAndPathName();
    if (!knackApp) return console.error("Subdomain not found");
    let builderUrl = `https://builder.knack.com/${knackApp.subdomain}/${knackApp.appname}`;
    builderUrl +=
      type === "scene"
        ? `/pages/${obj.key}`
        : type === "view"
          ? `/pages/${obj.scene.key}/views/${obj.key}/${obj.type}`
          : type === "object"
            ? `/schema/list/objects/${obj.key}/fields/`
            : type === "field"
              ? `/schema/list/objects/${obj.object_key}/fields/${obj.key}/settings`
              : null;
    window.open(builderUrl, "_blank");
  };
  const getIdPrefix = (str) => {
    const prefixes = ["view_", "scene_", "object_", "field_"];
    for (const prefix of prefixes) {
      if (str.startsWith(prefix)) {
        return prefix.slice(0, -1);
      }
    }
    return false;
  };
  const searchKnack = () => {
    const defaultButtonText = disableSearchButton(searchButton);
    const searchTerm = searchInput.value.trim().toLowerCase();
    const searchById = getIdPrefix(searchTerm);
    const searchType = searchById ? searchById : searchInput.dataset.type;
    const filters =
      searchTerm === ""
        ? []
        : searchById
          ? [{ property: "key", operator: "is", value: searchTerm }]
          : [
              {
                match: "or",
                rules: [
                  {
                    property: "title",
                    operator: "contains",
                    value: searchTerm,
                  },
                  { property: "name", operator: "contains", value: searchTerm },
                ],
              },
            ];
    const match = filterKnackModels(searchType, filters, false);
    resetSearchButton(defaultButtonText);
    if (searchById) {
      if (match && match.length > 0) {
        navigateToBuilder(searchType, match[0]);
        return console.info({ searchTerm, searchType, matches: match });
      } else {
        return alert(
          `No ${searchById}id found\nPlease doublecheck that the ${searchById}id used is correct: ${searchTerm}`,
        );
      }
    } else if (match && match.length > 0) {
      alert(
        `Matches found: ${match.length}\nRefer to console.log for search results.`,
      );
      return console.info({ searchTerm, searchType, matches: match });
    } else {
      console.log({ searchTerm, match });
      return alert(
        `No matches found\nPlease doublecheck the search term: ${searchTerm}\nIs correct for your search type of: ${searchType}`,
      );
    }
  };
  const resetSearchButton = (defaultButtonText) => {
    searchButton.textContent = defaultButtonText;
    searchButton.disabled = false;
  };
  const disableSearchButton = () => {
    const defaultButtonText = searchButton.textContent;
    searchButton.textContent = "Searching...";
    searchButton.disabled = true;
    return defaultButtonText;
  };
  const container = document.querySelector(elQuery);
  const { searchContainer, searchInput, searchButton, toggleSearchModeButton } =
    createSearchElements(searchKnack);
  container.appendChild(searchContainer);
};

const observer = new MutationObserver((mutationsList, observer) => {
  for (let mutation of mutationsList) {
    if (mutation.type === "childList") {
      mutation.addedNodes.forEach((node) => {
        if (node.nodeType === Node.ELEMENT_NODE) {
          const targetElement = node.matches("#knack-body header")
            ? node
            : node.querySelector("#pages-nav .title");
          if (targetElement) {
            targetElement.querySelector("#builder-search-container")
              ? observer.disconnect()
              : addSearchBar(
                  "#knack-body header .kn-container .knHeader__content",
                );
          }
        }
      });
    }
  }
});

observer.observe(document.body, {
  childList: true,
  subtree: true,
});

// CSV Export Functions
const findNestedProperties = (obj, path) => {
  const keys = path.split(".");
  let results = [];

  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];

    if (Array.isArray(obj)) {
      for (const item of obj) {
        const result = findNestedProperties(item, keys.slice(i).join("."));
        if (result) results = results.concat(result);
      }
      return results.length > 0 ? results : undefined;
    } else {
      obj = obj[key];
    }

    if (obj === undefined) return undefined;
  }

  return obj !== undefined ? [obj] : undefined;
};

// Get views using filters on all scenes or current scene
const getViewsByFilter = ({ filters, inThisScene = false, getKey = true }) => {
  const { models, viewsIgnore = [] } = inThisScene
    ? {
        models: [Knack.router.scene_view.model],
        viewsIgnore: Knack.router.scene_view.views_ignore,
      }
    : { models: Knack.scenes.models };

  return models.reduce((filteredKeys, { attributes: { views } }) => {
    views.forEach((view) => {
      if (viewsIgnore.includes(view.key)) return;
      const matches = filters.every((filterGroup) =>
        evaluateFilterGroup(view, filterGroup),
      );
      if (matches) filteredKeys.push(getKey ? view.key : view);
    });
    return filteredKeys;
  }, []);
};

// Applies rules for filter
const applyRule = (view, rule, returnValues = false) => {
  const { property, operator, value } = rule;
  const props = findNestedProperties(view, property);

  if (!props || !props.length) return false;
  if (!returnValues)
    return props.some((prop) => operators[operator](prop, value));
  return props.filter((prop) => operators[operator](prop, value));
};

// Evaluate a filter group using 'and'/'or' criteria
const evaluateFilterGroup = (view, group) => {
  const { match = "and", rules } = group;
  if (match === "and") {
    return rules.every((rule) => applyRule(view, rule));
  } else if (match === "or") {
    return rules.some((rule) => applyRule(view, rule));
  }
  return false;
};

const getBuilderBaseUrl = () => {
  const getSubdomainAndPathName = () => {
    const hostname = window.location.hostname;
    let pathName = window.location.pathname;
    if (pathName.endsWith("/")) pathName = pathName.slice(0, -1);
    const parts = hostname.split(".");
    const arr = [];
    if (parts.length >= 3) {
      arr.push(parts[0]);
      arr.push(pathName);
    }
    return arr;
  };
  const arrDomains = getSubdomainAndPathName();
  if (arrDomains.length === 0) return console.error("Subdomain not found");
  let builderUrl = `https://builder.knack.com/${arrDomains[0]}${arrDomains[1]}`;
  return builderUrl;
};

const getBuilderPath = ({
  path,
  type = "view",
  childPage,
  builderUrl = getBuilderBaseUrl(),
}) => {
  if (!builderUrl) builderUrl = getBuilderBaseUrl();

  switch (type) {
    case "scene":
      builderUrl += `/pages/${path.sceneKey}`;
      break;
    case "view":
      builderUrl += `/pages/${path.sceneKey}/views/${path.viewKey}/${path.type}`;
      break;
    case "object":
      builderUrl += `/schema/list/objects/${path.objectKey}/fields/`;
      break;
    case "field":
      builderUrl += `/schema/list/objects/${path.objectKey}/fields/${path.fieldKey}/settings`;
      break;
    default:
      builderUrl = null;
  }
  if (builderUrl && childPage) builderUrl += `/${childPage}`;
  return builderUrl;
};
const formatValueForCSV = (val) => {
  if (Array.isArray(val)) {
    return val.map((item) => formatValueForCSV(item)).join(", ");
  } else if (val && typeof val === "object") {
    console.log(val);
    return `${JSON.stringify(val)}`;
  }
  return val;
};

const convertArrToCSV = (arr) => {
  if (arr.length === 0) return "";

  const headers = Object.keys(arr[0]);
  const csvRows = arr.map((row) =>
    headers
      .map((header) => {
        let str = row[header].toString();
        str = str.replace(/\n/g, " "); // Replace newline characters with space
        str = str.replace(/"/g, '""'); // Escape double quotes
        str = str.replace(/; /g, "\n"); // Replace semicolons with spaces after with newlines
        return str.includes(",") || str.includes('"') ? `"${str}"` : str; // Enclose fields with commas or double quotes in double quotes
      })
      .join(","),
  );

  return [headers.join(","), ...csvRows].join("\n");
};
const downloadCSV = (content, fileName) => {
  const blob = new Blob([content], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");

  a.href = url;
  a.download = fileName;
  a.style.display = "none";

  document.body.appendChild(a);
  a.click();

  document.body.removeChild(a);
  URL.revokeObjectURL(url);
};

getKnackDataCsv = ({ type, autoDownload }) => {
  const builderUrl = getBuilderBaseUrl();
  let extractData;
  switch (type) {
    case "email":
      extractData = extractEmails;
      break;
    case "record-rule":
      extractData = extractRecordRules;
      break;
    case "scene":
      extractData = extractScenes;
      break;
    case "view":
      extractData = extractViews;
      break;
    case "object":
      extractData = extractObjects;
      break;
    case "field":
      extractData = extractFields;
      break;
    default:
      return console.error("Invalid type provided for CSV");
  }

  // Generate csv blob
  const results = extractData(builderUrl);
  const csv = convertArrToCSV(results);
  if (!autoDownload) return csv;

  // Download csv
  const getFormattedDate = () => {
    const now = new Date();
    const pad = (num) => String(num).padStart(2, "0");
    return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}`;
  };
  const dateStamp = getFormattedDate();
  const appSlug = Knack.app.attributes.slug;
  const fileName = `${appSlug}_${type}s_${dateStamp}.csv`;
  downloadCSV(csv, fileName);
};

const extractScenes = (builderUrl = getBuilderBaseUrl()) => {
  const scenes = Knack.scenes.models;
  const getData = (scene) => {
    const attributes = scene.attributes;
    const path = {
      sceneKey: attributes.key,
      objectKey: attributes.source?.object,
    };
    const url = getBuilderPath({ path, type: "scene", builderUrl });

    return [
      {
        scene_key: path.sceneKey,
        name: attributes.name || "",
        builder_url: url,
        authenticated:
          attributes.authenticated != null ? attributes.authenticated : "",
        object: attributes.object != null ? attributes.object : "",
        authentication_profiles:
          formatValueForCSV(attributes.authentication_profiles) || "",
        modal: attributes.modal != null ? attributes.modal : "",
        parent: attributes.parent || "",
        type: attributes.type || "",
        view_count: attributes.views?.length || 0,
        views: attributes.views
          ?.map((view) => ({
            key: view.key || "",
            type: view.type || "",
            name: view.name || "",
            title: view.title || "",
          }))
          .map(
            (obj) =>
              `key: ${obj.key}, type: ${obj.type}, name: ${obj.name}, title: ${obj.title}`,
          )
          .join("; "),
      },
    ];
  };

  const results = scenes.flatMap((scene) => getData(scene));
  return results;
};

const extractViews = (builderUrl = getBuilderBaseUrl()) => {
  const scenes = Knack.scenes.models;
  const getData = (view) => {
    const attributes = view.attributes;
    const path = {
      sceneKey: attributes.scene.key,
      viewKey: attributes.key,
      type: attributes.type,
      objectKey: attributes.source?.object,
    };
    const url = getBuilderPath({ path, builderUrl });
    let fields;
    switch (attributes.type) {
      case "form":
        fields = applyRule(
          attributes,
          {
            property: "groups.columns.inputs.field.key",
            operator: "contains",
            value: "field_",
          },
          true,
        );
        break;
      case "details":
      case "list":
        fields = applyRule(
          attributes,
          {
            property: "columns.groups.columns.key",
            operator: "contains",
            value: "field_",
          },
          true,
        );
        break;
      case "table":
        fields = applyRule(
          attributes,
          {
            property: "columns.field.key",
            operator: "contains",
            value: "field_",
          },
          true,
        );
        break;
      case "search":
        fields = applyRule(
          attributes,
          {
            property: "groups.columns.fields.field",
            operator: "contains",
            value: "field_",
          },
          true,
        );
        break;
      case "report":
        fields = applyRule(
          attributes,
          {
            property: "rows.reports.groups.field",
            operator: "contains",
            value: "field_",
          },
          true,
        );
        break;
      default:
        fields = "";
        break;
    }
    return [
      {
        scene_key: path.sceneKey || "",
        view_key: path.viewKey || "",
        object_key: path.objectKey || "",
        builder_url: url,
        type: attributes.type || "",
        ecommerce: attributes.ecommerce != null ? attributes.ecommerce : "",
        action: attributes.action || "",
        title: attributes.title || "",
        name: attributes.name || "",
        fields: formatValueForCSV(fields),
        email_rules_count: attributes.rules?.emails?.length || 0,
        field_rules_count: attributes.rules?.fields?.length || 0,
        record_rules_count: attributes.rules?.records?.length || 0,
        submit_rules_count: attributes.rules?.submits?.length || 0,
      },
    ];
  };
  const results = scenes.flatMap((scene) =>
    scene.views.models.flatMap((view) => getData(view)),
  );
  return results;
};

const extractObjects = (builderUrl = getBuilderBaseUrl()) => {
  const objects = Knack.objects.models;
  const getData = (object) => {
    const attributes = object.attributes;
    const path = { objectKey: attributes.key };
    const url = getBuilderPath({ path, type: "object", builderUrl });

    return [
      {
        object_key: path.objectKey,
        user: attributes.user != null ? attributes.user : false,
        name: attributes.name || "",
        builder_url: url,
        task_count: attributes.tasks?.length || 0,
        field_count: attributes.fields?.length || 0,
        inbound_connections: attributes.connections?.inbound
          ?.map((conn) => ({
            belong_to: conn.belongs_to || "",
            object: conn.object || "",
            field_name: conn.field?.name || "",
            field_key: conn.key || "",
          }))
          .map(
            (conn) =>
              `belong_to: ${conn.belong_to}, object: ${conn.object}, field_name: ${conn.field_name}, field_key: ${conn.field_key}`,
          )
          .join("; "),
        inbound_connections_count: attributes.connections?.inbound?.length || 0,
        outbound_connections: attributes.connections?.outbound
          ?.map((conn) => ({
            belong_to: conn.belongs_to || "",
            object: conn.object || "",
            field_name: conn.field?.name || "",
            field_key: conn.key || "",
          }))
          .map(
            (conn) =>
              `belong_to: ${conn.belong_to}, object: ${conn.object}, field_name: ${conn.field_name}, field_key: ${conn.field_key}`,
          )
          .join("; "),
        outbound_connections_count:
          attributes.connections?.outbound?.length || 0,
      },
    ];
  };

  const results = objects.flatMap((object) => getData(object));
  return results;
};

const extractFields = (builderUrl = getBuilderBaseUrl()) => {
  const objects = Knack.objects.models;
  const getData = (field) => {
    const attributes = field.attributes;
    const path = { objectKey: attributes.object_key, fieldKey: attributes.key };
    const url = getBuilderPath({ path, type: "field", builderUrl });

    return [
      {
        object_key: path.objectKey,
        field_key: path.fieldKey,
        type: attributes.type || "",
        name: attributes.name || "",
        builder_url: url,
        format: formatValueForCSV(attributes.format) || "",
        user: attributes.user != null ? attributes.user : "",
        required: attributes.required != null ? attributes.required : "",
        unqiue: attributes.unique != null ? attributes.unique : "",
        conditional:
          attributes.conditional != null ? attributes.conditional : "",
        has_validation_rules: attributes.validation?.length > 0 || "false",
        relationship: attributes.relationship
          ? `belongs_to: ${attributes.relationship.belongs_to}, has: ${attributes.relationship.has}, object: ${attributes.relationship.object}`
          : "",
      },
    ];
  };

  const results = objects.flatMap((object) =>
    object.fields.models.flatMap((field) => getData(field)),
  );
  return results;
};

const extractEmails = (builderUrl = getBuilderBaseUrl()) => {
  const scenes = Knack.scenes.models;
  const getData = (view) => {
    const attributes = view.attributes;
    const path = {
      sceneKey: attributes.scene.key,
      viewKey: attributes.key,
      type: attributes.type,
      objectKey: attributes.source?.object,
    };
    const url = getBuilderPath({ path, builderUrl, childPage: "emails" });
    return (
      attributes?.rules?.emails?.map((rule) => ({
        scene_key: path.sceneKey,
        view_key: path.viewKey,
        object_key: path.objectKey,
        builder_url: url,
        criteria: rule.criteria
          ?.map((obj) => ({
            field: obj.field || "",
            operator: obj.operator,
            value: formatValueForCSV(obj.value),
          }))
          .map(
            (obj) =>
              `field: ${obj.field}, operator: ${obj.operator}, value: ${obj.value}`,
          )
          .join("; "),
        from_email: rule.email.from_email || "",
        from_name: rule.email.from_name || "",
        subject: rule.email.subject || "",
        recipients: rule.email.recipients
          ? rule.email.recipients
              .map((recipient) => recipient.email || "")
              .join(", ")
          : "",
        message: rule.email.message || "",
      })) || []
    );
  };
  const results = scenes.flatMap((scene) =>
    scene.views.models.flatMap((view) => getData(view)),
  );
  return results;
};

const extractRecordRules = (builderUrl = getBuilderBaseUrl()) => {
  const scenes = Knack.scenes.models;
  const getData = (view) => {
    const attributes = view.attributes;
    const path = {
      sceneKey: attributes.scene.key,
      viewKey: attributes.key,
      type: attributes.type,
      objectKey: attributes.source?.object,
    };
    const url = getBuilderPath({ path, builderUrl, childPage: "rules/record" });
    return (
      attributes?.rules?.records?.map((rule) => ({
        scene_key: path.sceneKey,
        view_key: path.viewKey,
        object_key: path.objectKey,
        builder_url: url,
        connection: rule.connection || "",
        //criteria: formatValueForCSV(rule.criteria),
        criteria: rule.criteria
          ?.map((obj) => ({
            field: obj.field || "",
            operator: obj.operator,
            value: formatValueForCSV(obj.value),
          }))
          .map(
            (obj) =>
              `field: ${obj.field}, operator: ${obj.operator}, value: ${obj.value}`,
          )
          .join("; "),
        //values: formatValueForCSV(rule.values),
        values: rule.values
          ?.map((obj) => ({
            connection_field: obj.connection_field || "N/A",
            field: obj.field,
            input: obj.input,
            type: obj.type,
            value: formatValueForCSV(obj.value),
          }))
          .map(
            (obj) =>
              `connection_field: ${obj.connection_field}, field: ${obj.field}, input: ${obj.input}, type: ${obj.type}, value: ${obj.value}`,
          )
          .join("; "),
      })) || []
    );
  };
  const results = scenes.flatMap((scene) =>
    scene.views.models.flatMap((view) => getData(view)),
  );
  return results;
};
