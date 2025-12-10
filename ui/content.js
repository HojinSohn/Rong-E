(function() {
    // 1. Prevent Double Injection (But allow toggling if already exists)
    const existingBox = document.getElementById("echo-overlay");
    if (existingBox) {
        // If it exists but is hidden, toggle it now
        // This handles the case where the script is re-executed by some other means
        // typically the listener below handles the toggle, but this is a safety check.
        return; 
    }

    // 2. Create the UI Container
    const box = document.createElement("div");
    box.id = "echo-overlay";
    box.innerHTML = `
        <div id="echo-header">
            ECHO TERMINAL v1.0 
            <span id="echo-close" style="float:right; cursor:pointer;">&times;</span>
        </div>
        <div id="echo-messages"></div>
        <input id="echo-input" placeholder="Enter command..." autocomplete="off" />
    `;
    document.body.appendChild(box);

    const msgBox = document.getElementById("echo-messages");
    const input = document.getElementById("echo-input");
    const closeBtn = document.getElementById("echo-close");

    // --- TOGGLE LOGIC (NEW) ---
    // Listen for the message from background.js
    chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
        if (request.action === "toggle_overlay") {
            if (box.style.display === "none") {
                box.style.display = "flex";
                input.focus(); // Focus input when opening
            } else {
                box.style.display = "none";
            }
        }
    });

    // Also allow closing via the "X" button
    closeBtn.addEventListener("click", () => {
        box.style.display = "none";
    });

    // --- SEND LOGIC (EXISTING) ---
    async function send(msg) {
        const userDiv = document.createElement("div");
        userDiv.className = "echo-msg-user";
        userDiv.innerHTML = `> ${msg}`;
        msgBox.appendChild(userDiv);
        msgBox.scrollTop = msgBox.scrollHeight;

        const pageText = document.body.innerText.slice(0, 5000); // limit length

        try {
            const response = await fetch("http://localhost:8000/chat", {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({ message: msg, page_content: pageText, url: window.location.href})
            });

            const data = await response.json();

            const aiDiv = document.createElement("div");
            aiDiv.className = "echo-msg-ai";
            aiDiv.innerHTML = `<b>ECHO:</b> ${data.response}`;
            msgBox.appendChild(aiDiv);
            
        } catch (err) {
            console.error(err);
            const errDiv = document.createElement("div");
            errDiv.className = "echo-msg-error";
            errDiv.innerText = `[ERROR]: Cannot reach Python server.`;
            msgBox.appendChild(errDiv);
        }
        
        msgBox.scrollTop = msgBox.scrollHeight;
    }

    input.addEventListener("keydown", (e) => {
        if (e.key === "Enter" && input.value.trim()) {
            send(input.value.trim());
            input.value = "";
        }
    });
})();