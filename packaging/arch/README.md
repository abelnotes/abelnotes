# Arch Linux package

`PKGBUILD` for `abelnotes-bin`, which repackages the release `.deb` for Arch.

    makepkg -si

Bump `pkgver` and `_build` for a new release, then run `updpkgsums` and
`makepkg --printsrcinfo > .SRCINFO`.
