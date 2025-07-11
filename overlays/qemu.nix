self: super: {
  qemu = super.qemu.override {
    rutabagaSupport = true;
    openGLSupport = true;
    minimal = false;
    toolsOnly = false;
    userOnly = false;
  };

  # Patch the meta.availableOn check to always say true for rutabaga_gfx
  rutabaga_gfx = super.rutabaga_gfx.overrideAttrs (old: {
    meta = old.meta or {} // {
      availableOn = _platform: true;
    };
  });
}
