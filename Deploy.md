# **Deployment**

Steps to deploy an updated version.

## **Make updates**

1. Git stage and commit any changes: updated .toc file, etc.
2. Git Push commit to GitHub.

## **Trigger build pipeline:**

Git add a new tag for the new version number: 

1. Vscode: Ctrl+shift+p -> 'Git: Create Tag'. The tag should be the new retail build version number
2. Push the tag to GitHub to trigger the Github Actions build pipeline: VSCode: Ctrl+shift+p -> 'Git: Push (Follow Tags)'

Note: Pipeline script: .github\workflows\release.yml

### **Verify**

- Check https://github.com/nrpieper/wow-misspelled/actions to watch build.
- When finished confirm new release is available on github: https://github.com/nrpieper/wow-misspelled
- Check CurseForge to see if the latest version deployed successfully: https://www.curseforge.com/wow/addons/misspelled
