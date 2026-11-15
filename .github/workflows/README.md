# Release safety

The first standalone **v4.0.0** release is deliberately manual. Before running the Release workflow:
1. Create and push the standalone repository `wwwwzzzzkkkk/ChipBar` on `main`.
2. Capture and verify authentic high-resolution screenshots of the **running** v4 build and update README.
3. Confirm both Chinese and English UI, including diagnostics, pairing and update states.
4. Complete CI and verify the app uses the new GitHub Release location.
5. Confirm the third-party macmon package is still required (it is **not** bundled or notarized).
6. Start the manual release workflow and verify the immutable `v4.0.0` tag and archived checksum.

The application never controls OpenFAST simulation tasks.
