# stepkeeper-apple manual test guide

## Setup
- A server is optional — the default is direct mode (key only). The stub/real server is for development and regression runs.
- Local server (development/regression): `cd ../stepkeeper-server && python app.py` (real analysis) or `python3 scripts/stub-server.py` (stub)
- Real analysis needs your own Gemini key (free from AI Studio) — enter it in the app's settings
- To use a development server, enter its URL in settings — `127.0.0.1:8787` on the simulator, your Mac's LAN IP on a device

## Checklist
1. [ ] Settings: save the key → still there after restarting the app (Keychain)
2. [ ] Home: paste a YouTube URL → "Make document" enables (disabled for an invalid URL)
3. [ ] Analysis: player appears → title/length shown → profile auto-detected ("Cooking" for a cooking video) → start analysis
4. [ ] Picking: three candidates per guide plus "doesn't fit", center pre-selected, selection changeable
5. [ ] Document: picked images render; guides set to "doesn't fit" or that failed capture show a ▶ timestamp link
6. [ ] Export: share sheet carries md+jpg / "Save to a folder" then open in Obsidian or similar
7. [ ] Link mode ON: document builds from links only, no capture
8. [ ] Share extension (iOS): share from Safari/the YouTube app → stepkeeper → opening the app starts it automatically
9. [ ] Share two videos **before** opening the app → the first analyzes on open, Home shows "Analyze next shared video (1 waiting)", tapping it runs the second (nothing silently lost)
9-1. [ ] Share extension (iOS) cold start: with stepkeeper **fully quit**, share → open the app fresh → it starts with the shared URL
10. [ ] Errors: start without a key (key notice), with the server down (connection notice), with an invalid URL
11. [ ] macOS: 1–7 behave the same
12. [ ] Back-to-back analyses: right after a document completes, analyze a different video → the second video's title and length are correct (showing the previous video's is a bug)
13. [ ] Share a different video from the YouTube app **while analysis/capture is running** → returning to stepkeeper switches cleanly to the new flow (mixed-in frames from the previous video is a bug)
14. [ ] Notion export: create an integration at notion.so/my-integrations → add it to the target page under ··· → Connections → enter the token and page URL in settings → "Send to Notion" on the document screen → check images and timestamp links in Notion. Error cases: bad token (401 notice), unconnected page (parent-page notice)
15. [ ] Direct mode (default): with the server URL empty, analyze → completes with no local server process (only the Gemini key)
16. [ ] Report with no collector: with both the server and report URLs empty, tap 🚩 → the sheet explains the mail fallback before sending

## Languages
17. [ ] Set the device/simulator to English → the whole UI is English (settings, toolbar, progress, errors)
18. [ ] Set the document language to Korean, make a document, then switch the **device** to English → the document body stays Korean (only the UI switches)
19. [ ] Document language `ja` → the body is Japanese and the scaffolding (section titles, source line) is English, never Korean

## AI frame picking (off by default)
20. [ ] Turn "AI picks the frame" on → after capture, the picker opens with the AI's choice pre-selected and a one-line reason per guide
21. [ ] Turn it off → the picker opens on center as before, with no reasons
22. [ ] With the toggle on but no key saved → a notice explains it, and picking continues manually
23. [ ] After a few documents with the toggle on, Settings shows "You kept N of M AI picks"; "Reset AI pick stats" clears it. The number never leaves the device

## Reproducing 429 (free-tier limit)
- Run three or more analyses in quick succession → confirm the "try again in a moment" notice
