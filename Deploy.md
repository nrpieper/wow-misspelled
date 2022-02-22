**Deployment**

Steps to deploy an updated version.

**Make updates***
Git stage and commit any changes: updated .tod file, etc.

**Trigger build pipeline:**
Git add a new tag for the new version number: Vscode: Ctrl+shift+p -> 'Git: Create Tag'
Push the tag to GitHub to trigger the Travis-CI.com build pipeline: VSCode: Ctrl+shift+p -> 'Git: Push (Follow Tags)'
Pipeline script: .travis.yml 

**Verify**
Check https://app.travis-ci.com to watch build.
When finished confirm new release is available on github: https://github.com/nrpieper/wow-misspelled
Check Curse to see if the latest version deployed successfully: 
