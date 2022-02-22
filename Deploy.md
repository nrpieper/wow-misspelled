# **Deployment**

Steps to deploy an updated version.

## **Make updates**

1. Git stage and commit any changes: updated .tod file, etc.
2. Git Push commit to GitHub.

## **Trigger build pipeline:**

Git add a new tag for the new version number: 

1. Vscode: Ctrl+shift+p -> 'Git: Create Tag'
2. Push the tag to GitHub to trigger the Travis-CI.com build pipeline: VSCode: Ctrl+shift+p -> 'Git: Push (Follow Tags)'

Note: Pipeline script: .travis.yml 

### **Verify**

- Check https://app.travis-ci.com to watch build.
- When finished confirm new release is available on github: https://github.com/nrpieper/wow-misspelled
- Check Curse to see if the latest version deployed successfully: 
