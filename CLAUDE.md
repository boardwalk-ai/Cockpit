# Octopilot

## Releases

The release page is https://octopilothub.com/app/releases/. It is built from
`releases.json` on the server; there is no release page file in this repo to
edit (`tools/releases-page/index.html` is the page's template, not the list).

To release the app: upload the APK to Drive (`/drive-release:release`), then
publish it with the Drive link:

    bash tools/releases-page/publish.sh "<drive link>" <version> <build> "note" ["note" ...]

The link must be shared as "anyone with the link"; the server downloads it
itself. Never publish the admin app.
