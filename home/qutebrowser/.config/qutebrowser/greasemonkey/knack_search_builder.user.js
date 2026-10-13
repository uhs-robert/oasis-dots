// ==UserScript==
// @name        Knack Builder - Add Search by Scene/View
// @namespace   Violentmonkey Scripts
// @match       https://builder.knack.com/*
// @grant       none
// @version     1.0
// @author      Robert Hill
// @description 2/22/2024, 4:49:24 PM
// ==/UserScript==
const createSearchElements = (placeholderText, handleSearchFunction, width) => {
  const searchContainer = document.createElement("div");
  searchContainer.classList.add("level-right");
  searchContainer.style.marginRight = "1em";
  const searchBar = document.createElement("input");
  searchBar.type = "text";
  searchBar.placeholder = placeholderText;
  searchBar.style.width = width ? width : "80%";
  searchBar.classList.add("search-bar");
  const searchButton = document.createElement("button");
  searchButton.textContent = "Search";
  searchButton.style.width = "max-content";
  searchButton.classList.add("search-button");
  searchButton.style.cssText =
    "cursor: pointer; padding: 10px; background-color: #3DB5FF; color: white; margin-left: 10px; border: none; border-radius: 10px;";
  searchButton.addEventListener("click", handleSearchFunction);
  searchBar.addEventListener("keypress", (event) => {
    if (event.key === "Enter") handleSearchFunction();
  });
  return { searchContainer, searchBar, searchButton };
};
const addSceneSearch = (elQuery) => {
  const expandOrCollapseTreeItems = (expand = true) => {
    return new Promise((resolve, reject) => {
      let attempts = 0;
      const maxAttempts = 30;
      const intervalTime = 500;
      const interval = setInterval(() => {
        let selector = expand ? ".tree-expand:not(.open)" : ".tree-expand.open";
        document.querySelectorAll(selector).forEach((el) => el.click());
        if (
          document.querySelectorAll(selector).length === 0 ||
          attempts > maxAttempts
        ) {
          clearInterval(interval);
          resolve();
        }
        attempts++;
      }, intervalTime);
    });
  };
  const resetColors = () => {
    document.querySelectorAll("#pages-nav .name").forEach((el) => {
      el.style.backgroundColor = "";
    });
  };
  const handleSearch = async () => {
    const originalButton = searchButton.textContent;
    searchButton.textContent = "Searching...";
    searchButton.disabled = true;
    resetColors();
    const search = searchBar.value.trim().toLowerCase();
    if (!search) {
      await expandOrCollapseTreeItems();
    } else {
      await expandOrCollapseTreeItems();
      const isSceneID = search.startsWith("scene_");
      let scene = null;
      let count = 0;
      if (isSceneID) {
        scene = document.getElementById(`page-link-${search}`);
      } else {
        document.querySelectorAll("#pages-nav .name").forEach((el) => {
          if (el.textContent.toLowerCase().includes(search)) {
            if (count === 0) scene = el.closest("li");
            count++;
            el.style.backgroundColor = "yellow";
          }
        });
      }
      if (scene) {
        const pagesNav = document.getElementById("pages-nav");
        const scrollTop = scene.offsetTop - pagesNav.offsetTop - 100;
        pagesNav.scrollTo({
          top: scrollTop,
          behavior: "smooth",
        });
        setTimeout(() => {
          const link = scene.querySelector("a");
          if (link) link.click();
          if (count > 0) alert(`Multiple matches found: ${count}`);
        }, 1500);
      } else {
        alert(`No matches found for search: ${search}`);
      }
    }
    searchButton.textContent = originalButton;
    searchButton.disabled = false;
  };
  const container = document.querySelector(elQuery);
  const { searchContainer, searchBar, searchButton } = createSearchElements(
    "Search scenes...",
    handleSearch,
  );
  container.appendChild(searchContainer);
  searchContainer.appendChild(searchBar);
  searchContainer.appendChild(searchButton);
  const { scene_id } = getSceneAndViewFromUrl();
  searchBar.value = scene_id;
};
const addViewSearch = (elQuery) => {
  const resetColors = () => {
    document.querySelectorAll("#page-views .kn-title").forEach((el) => {
      el.style.backgroundColor = "";
    });
  };
  const handleSearch = async () => {
    const originalButton = searchButton.textContent;
    searchButton.textContent = "Searching...";
    searchButton.disabled = true;
    resetColors();
    const search = searchBar.value.trim().toLowerCase();
    if (search) {
      const isID = search.startsWith("view_");
      let view = null;
      let count = 0;
      if (isID) {
        view = document.querySelector(`.${search}`);
      } else {
        document
          .querySelectorAll("#page-views .kn-container .kn-title")
          .forEach((el) => {
            if (el.textContent.toLowerCase().includes(search)) {
              if (count === 0) view = el;
              count++;
              el.style.backgroundColor = "yellow";
            }
          });
      }
      if (view) {
        const bodyScroll = document.getElementById("body-scroll");
        const viewExpand = view.querySelector(".blur");
        bodyScroll.scrollTo({
          top: viewExpand.offsetTop,
          behavior: "smooth",
        });
        if (view && !view.classList.contains("is-active")) viewExpand.click();
        if (count > 0) alert(`Multiple matches found: ${count}`);
      } else {
        alert(`No matches found for search: ${search}`);
      }
    }
    searchButton.textContent = originalButton;
    searchButton.disabled = false;
  };
  const container = document.querySelector(`${elQuery} .ribbon_subRow`);
  const { searchContainer, searchBar, searchButton } = createSearchElements(
    "Search views...",
    handleSearch,
  );
  container.appendChild(searchContainer);
  searchContainer.appendChild(searchBar);
  searchContainer.appendChild(searchButton);
  const { view_id } = getSceneAndViewFromUrl();
  searchBar.value = view_id;
};
const getSceneAndViewFromUrl = () => {
  const url = window.location.href;
  const pathName = new URL(url).pathname;
  const segments = pathName.split("/");
  const obj = { scene_id: "", view_id: "" };
  segments.forEach((segment) => {
    if (segment.startsWith("scene_")) {
      obj.scene_id = segment;
    } else if (segment.startsWith("view_")) {
      obj.view_id = segment;
    }
  });
  return obj;
};
const pageObserver = new MutationObserver((mutationsList, observer) => {
  for (let mutation of mutationsList) {
    if (mutation.type === "childList") {
      mutation.addedNodes.forEach((node) => {
        if (node.nodeType === Node.ELEMENT_NODE) {
          const pageNav = node.matches("#pages-nav .title")
            ? node
            : node.querySelector("#pages-nav .title");
          const pageRibbon = node.matches("#page-ribbon")
            ? node
            : node.querySelector("#page-ribbon");
          if (pageNav) addSceneSearch("#pages-nav .title");
          if (pageRibbon) addViewSearch("#page-ribbon");
        }
      });
    }
  }
});
pageObserver.observe(document.body, {
  childList: true,
  subtree: true,
});
