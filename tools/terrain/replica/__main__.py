"""CLI entry: python -I -m replica {fetch|build|check} <site>."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _no_download(url: str) -> bytes:
    raise RuntimeError("not in the cache")


def build(site_dir: Path) -> int:
    """fetch-cache check (no downloads) -> ortho -> classes (+overrides) -> rocks (detect +
    merge edits) -> heightmaps -> rule fill + mass packing (placed rocks, scatter, grass
    density) -> export (Ruling 7)."""
    import time

    import numpy as np
    from PIL import Image

    from .classify import write_classes
    from .export import export_site, write_hillshade_debug
    from .fetch import FetchError, fetch_dem, fetch_imagery
    from .geo import LocalFrame
    from .heightmap import (
        agreement_failures, block_residuals, core_dem30, core_heightmap, core_n, drift_check,
        is_large_mass, mass_top_surface, ring_heightmap, upsample_dem,
    )
    from .rasters import dem_grid, read_dem, write_ortho
    from .rocks import write_site_rocks
    from .scatter import site_scatter, type_counts
    from .site import SiteConfig

    t0 = time.perf_counter()
    last = [t0]

    def step(name: str) -> None:
        now = time.perf_counter()
        print(f"  {name}: {now - last[0]:.1f} s")
        last[0] = now

    cfg = SiteConfig.load(site_dir)
    try:
        dem_paths = fetch_dem(cfg, downloader=_no_download)
        tiles = fetch_imagery(cfg, downloader=_no_download)
    except FetchError as exc:
        print(
            f"replica build: cache incomplete ({exc}); run `python -I -m replica fetch "
            f"{site_dir}` first",
            file=sys.stderr,
        )
        return 1
    frame = LocalFrame(cfg.lat, cfg.lon)
    print(f"replica build {cfg.name}")
    write_ortho(cfg, frame, tiles)
    step("ortho")
    write_classes(cfg)
    step("classes")
    detected, rocks = write_site_rocks(cfg)
    step(f"rocks ({len(detected)} detected, {len(rocks)} after edits)")
    with Image.open(cfg.build_dir / "classes_full.png") as im:
        classes = np.asarray(im)
    dems = read_dem(dem_paths)
    dem30 = core_dem30(cfg, frame, dems)
    up = upsample_dem(dem30, cfg)
    core = core_heightmap(dem30, classes, rocks, cfg)
    tops = mass_top_surface(dem30, rocks, cfg, up)
    step("core heightmap")
    res = block_residuals(core, rocks, dem30, cfg, tops)
    native = dem_grid(cfg, frame, cfg.core_m / 2.0, cfg.core_step_m, dems)
    if native.shape != (core_n(cfg),) * 2:
        raise ValueError(f"native DEM grid {native.shape} != core grid")
    stats = {
        "agreement_rms_m": float(np.sqrt(np.mean(res * res))),
        "agreement_max_m": float(np.abs(res).max()),
        **drift_check(core, rocks, dem30, native, cfg),
        "large_masses": sum(1 for r in rocks if is_large_mass(r)),
    }
    stats = {k: round(v, 3) if isinstance(v, float) else v for k, v in stats.items()}
    step("agreement checks")
    ring = ring_heightmap(cfg, frame, dems)
    step("ring heightmap")
    placed, scatter, grass = site_scatter(cfg, classes, core, rocks, tops)
    counts = ", ".join(f"{k} {v}" for k, v in type_counts(scatter).items())
    step(f"rule fill ({len(placed)} placed rocks; {counts})")
    export_site(cfg, core, ring, classes, rocks, scatter, mass_tops=tops, stats=stats,
                placed=placed, grass=grass)
    write_hillshade_debug(cfg, core)
    step("export")
    print(
        f"DEM agreement (30 m blocks): rms {stats['agreement_rms_m']:.3f} m, "
        f"max {stats['agreement_max_m']:.3f} m"
    )
    print(
        f"vs native DEM: rms {stats['native_rms_m']:.3f} m, max {stats['native_max_m']:.3f} m; "
        f"rock-free ground ({stats['rock_free_blocks']} blocks): "
        f"rms {stats['rock_free_rms_m']:.3f} m, max {stats['rock_free_max_m']:.3f} m"
    )
    print(f"total {time.perf_counter() - t0:.1f} s")
    failures = agreement_failures(stats)
    if failures:
        print("replica build: DEM agreement over plan thresholds (outputs written for "
              "inspection): " + "; ".join(failures), file=sys.stderr)
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="replica")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("fetch", "build", "check"):
        p = sub.add_parser(name)
        p.add_argument("site", nargs="?", default="sumber")
    args = parser.parse_args(argv)
    if args.command == "fetch":
        from .fetch import FetchError, fetch_dem, fetch_imagery
        from .site import SiteConfig

        try:
            cfg = SiteConfig.load(Path(args.site))
            dem = fetch_dem(cfg)
            tiles = fetch_imagery(cfg)
        except FetchError as exc:
            print(f"replica fetch: {exc}", file=sys.stderr)
            return 1
        print(f"DEM tiles: {len(dem)}")
        for p in dem:
            print(f"  {p} ({p.stat().st_size} bytes)")
        print(f"imagery tiles: {len(tiles)}")
        return 0
    if args.command == "build":
        return build(Path(args.site))
    from .check import check_site

    return check_site(Path(args.site))


if __name__ == "__main__":
    sys.exit(main())
