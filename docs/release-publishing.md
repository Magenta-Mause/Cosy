Use this checklist whenever you publish a new COSY version.

## Release Process

1. Create a `feature/v<version-number>` branch on the [Cosy repository](https://github.com/Magenta-Mause/Cosy).
2. Update the `COSY_TAG` variable inside the `install_cosy.sh` to the new version number.
3. Update the quick install commands in the README to use the new published version.
4. Create a `feature/v<version-number>` branch on the [Cosy-Landing-Page repository](https://github.com/Magenta-Mause/Cosy-Landing-Page).
5. Update `COSY_VERSION` to the new version in `src/lib/constants.ts`.
6. Merge both branches.
7. Create a new release on the Cosy repository with a comprehensive changelog.
