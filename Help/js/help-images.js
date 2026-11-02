(() => {
    "use strict";

    function filename(fromSource) {
        try {
            const path = new URL(fromSource, document.baseURI).pathname;
            const name = path.slice(path.lastIndexOf("/") + 1);
            return decodeURIComponent(name) || "image";
        } catch {
            return "image";
        }
    }

    function replaceFailedImage(image) {
        if (image.dataset.helpImageFallback === "true") {
            return;
        }

        image.dataset.helpImageFallback = "true";
        const imageSource = image.getAttribute("src") || "";
        const missingFilename = filename(imageSource);
        const alternativeText = image.getAttribute("alt");
        const fallback = document.createElement("div");
        const message = document.createElement("span");
        const name = document.createElement("span");

        fallback.className = "help-image-fallback";
        fallback.setAttribute("role", "img");
        fallback.setAttribute(
            "aria-label",
            alternativeText
                ? `Image file not found: ${missingFilename}. ${alternativeText}`
                : `Image file not found: ${missingFilename}`
        );
        message.className = "help-image-fallback__message";
        message.textContent = "Image file not found";
        name.className = "help-image-fallback__filename";
        name.textContent = missingFilename;
        fallback.append(message, name);
        image.replaceWith(fallback);
    }

    function observeImage(image) {
        if (!image.getAttribute("src")) {
            return;
        }

        image.addEventListener("error", () => replaceFailedImage(image), { once: true });

        if (image.complete && image.naturalWidth === 0) {
            replaceFailedImage(image);
        }
    }

    function initialize() {
        document.querySelectorAll("img").forEach(observeImage);
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", initialize, { once: true });
    } else {
        initialize();
    }
})();
