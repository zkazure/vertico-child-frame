# vertico-child-frame

Display [Vertico](https://github.com/minad/vertico) in a native Emacs child frame — with zero external dependencies beyond `vertico` itself.

## Why `vertico-child-frame`?

Existing child-frame extensions for Vertico (`vertico-posframe` and `vertico-buffer-frame`) suffer from frame recreation overhead, compositor flicker, broken recursive minibuffer stacking, long-path jitter, or misaligned annotations. `vertico-child-frame` is built directly on Emacs 29/30+ native child-frame primitives to solve these cleanly:

| Feature | `vertico-child-frame` | `vertico-posframe` | `vertico-buffer-frame` |
| --- | --- | --- | --- |
| External dependencies | None (only `vertico`) | `posframe` | None (wraps `vertico-buffer`) |
| Frame reuse | Per-depth frame pool | Single `posframe` buffer/frame | `display-buffer-in-child-frame` |
| Geometry caching | Skips no-op move/resize calls | Re-evaluates per update | Re-evaluates via `display-buffer` |
| Positioning | 27 poshandlers (frame, window, other-window, point) + shorthand + offset | `posframe-poshandler-*` | `display-buffer-in-child-frame` |
| Sizing controls | Width/height (ratio, cols/lines, fn), min/max bounds, resize modes | Width/height/min-width/min-height | `display-buffer` sizing |
| Recursive minibuffers | Depth-indexed pool + cascade offset + outer re-raise | Overlapping / focus quirks | Window layout interference |
| Long-path stability | Auto-wrapping (`'auto`), `auto-hscroll-mode 'current-line`, `resize-mini-windows nil` | Known `C-x C-f` jitter & clipping | Inherits buffer window wrapping |
| Parent resize adaptation | Live resize & re-center via `window-size-change-functions` | Static until next update | Static until next update |
| Marginalia / grid width | Advises `vertico--window-width` to child frame | Needs workarounds / mismatches | Uses buffer window width |
| Default placement | Top-center command palette (keeps Consult preview clear) | Center of frame (blocks previews) | Buffer-dependent |
| `vertico-multiform` + TTY fallback | Native toggle (`M-C`) + automatic fallback mode | Manual `vertico-multiform` setup | Tied to `vertico-buffer-mode` |

## Requirements

- **GNU Emacs** 29.1 or newer (tested on Emacs 30.2, Linux X11 / Wayland `pgtk`)
- **Vertico** 1.0 or newer

## Installation

### `use-package` with `:vc` (Emacs 30+)

```elisp
(use-package vertico-child-frame
  :vc (:url "https://github.com/zkazure/vertico-child-frame"
       :rev :newest)
  :after vertico
  :config
  (vertico-child-frame-mode 1))
```

### `straight.el`

```elisp
(use-package vertico-child-frame
  :straight (:host github :repo "zkazure/vertico-child-frame")
  :after vertico
  :config
  (vertico-child-frame-mode 1))
```

### `elpaca`

```elisp
(use-package vertico-child-frame
  :ensure (:host github :repo "zkazure/vertico-child-frame")
  :after vertico
  :config
  (vertico-child-frame-mode 1))
```

### Manual

Clone this repository and add it to `load-path`:

```elisp
(add-to-list 'load-path "/path/to/vertico-child-frame")
(require 'vertico-child-frame)
(vertico-child-frame-mode 1)
```

## Configuration

### Global mode (Command Palette style)

By default, `vertico-child-frame-mode` opens a top-centered floating child frame (`0.6` of parent width, fixed height from `vertico-count`) so the lower editing area remains unobstructed for `consult` live previews:

```elisp
(vertico-mode 1)
(vertico-child-frame-mode 1)
```

### Sizing, position, and appearance example

```elisp
(setq vertico-child-frame-poshandler 'frame-center ; or #'vertico-child-frame-poshandler-point-bottom-left-corner
      vertico-child-frame-width 0.55               ; fraction (0.0-1.0], integer columns, or fn
      vertico-child-frame-height 16                ; nil (auto), integer lines, fraction, or fn
      vertico-child-frame-min-width 50             ; columns, fraction, or nil
      vertico-child-frame-max-width 110            ; columns, fraction, or nil
      vertico-child-frame-internal-border-width 8  ; inner padding in pixels
      vertico-child-frame-border-width 1
      vertico-child-frame-alpha 95)                ; background opacity (0-100) or (ACTIVE . INACTIVE)
```

### `vertico-multiform` integration (per-command position and size)

`vertico-child-frame` registers `vertico-child-frame-mode` in `vertico-multiform--display-modes` and defines `vertico-multiform-child-frame` (bound to `M-C` in `vertico-multiform-map` if unbound).

Do **not** enable `(vertico-child-frame-mode 1)` globally if you want `vertico-multiform-mode` to control it per command or category:

```elisp
(require 'vertico-child-frame)
(require 'vertico-multiform)

(setq vertico-multiform-commands
      '((consult-line buffer)
        (consult-ripgrep child-frame
                         (vertico-child-frame-poshandler . frame-bottom-center)
                         (vertico-child-frame-width . 0.8)
                         (vertico-child-frame-height . 18))
        (completion-at-point child-frame
                             (vertico-child-frame-poshandler . point-bottom-left-corner)
                             (vertico-child-frame-width . 55))
        (t child-frame)))

(vertico-multiform-mode 1)
```

### `consult` and `embark`

- **Consult live previews**: The default `vertico-child-frame-poshandler-frame-top-center` keeps the middle and lower portions of your frame visible so live buffer/file previews remain readable.
- **Embark recursive actions**: Recursive minibuffers (`enable-recursive-minibuffers t`) each receive their own pooled child frame for their `(minibuffer-depth)`, shifted by `vertico-child-frame-recursive-offset` (default `(24 . 24)` pixels). Exiting the inner prompt hides the nested frame and re-raises the outer session's frame automatically.

### TTY / small-frame fallback

When running in a terminal (`emacs -nw`) without child-frame support or when the parent frame is smaller than `vertico-child-frame-min-parent-width` / `vertico-child-frame-min-parent-height`, `vertico-child-frame` automatically steps aside and optionally enables `vertico-child-frame-fallback-mode` for the duration of that session:

```elisp
(setq vertico-child-frame-fallback-mode #'vertico-buffer-mode)
```

Leave `vertico-child-frame-fallback-mode` as `nil` to fall back to the standard bottom minibuffer.

## Poshandlers

`vertico-child-frame-poshandler` accepts a full function symbol, a short symbol (e.g. `'frame-center`), or a custom `(lambda (parent width height) (cons x y))` returning pixel coordinates relative to `parent`. You can also switch positions interactively with `M-x vertico-child-frame-set-poshandler`.

### Frame-relative

- `frame-top-center` / `vertico-child-frame-poshandler-frame-top-center` *(default, alias `...-top-center`)* — horizontally centered at `vertico-child-frame-top-offset` (`nil`, matching vertical margin)
- `frame-center` / `vertico-child-frame-poshandler-frame-center` *(alias `...-center`)* — dead center of the parent frame
- `frame-bottom-center` / `vertico-child-frame-poshandler-frame-bottom-center` *(alias `...-bottom-center`)* — horizontally centered near the bottom at `vertico-child-frame-bottom-offset` (`nil`, matching vertical margin)
- `frame-top-left-corner` / `vertico-child-frame-poshandler-frame-top-left-corner` — top-left corner inside margins
- `frame-top-right-corner` / `vertico-child-frame-poshandler-frame-top-right-corner` — top-right corner inside margins
- `frame-bottom-left-corner` / `vertico-child-frame-poshandler-frame-bottom-left-corner` — bottom-left corner inside margins
- `frame-bottom-right-corner` / `vertico-child-frame-poshandler-frame-bottom-right-corner` — bottom-right corner inside margins
- `frame-top-left-or-right-other-corner` / `vertico-child-frame-poshandler-frame-top-left-or-right-other-corner` — top corner opposite the active window

### Window-relative (relative to `(minibuffer-selected-window)`)

- `window-center` / `vertico-child-frame-poshandler-window-center`
- `window-top-center` / `vertico-child-frame-poshandler-window-top-center`
- `window-top-left-corner` / `vertico-child-frame-poshandler-window-top-left-corner`
- `window-top-right-corner` / `vertico-child-frame-poshandler-window-top-right-corner`
- `window-bottom-center` / `vertico-child-frame-poshandler-window-bottom-center`
- `window-bottom-left-corner` / `vertico-child-frame-poshandler-window-bottom-left-corner`
- `window-bottom-right-corner` / `vertico-child-frame-poshandler-window-bottom-right-corner`

### Other-window-relative (splits without obscuring the active window)

Positions relative to the next regular window on the parent frame (skipping `no-other-window` sidebars and the minibuffer), falling back to the corresponding `window-*` poshandler in a single-window frame:

- `other-window-center` / `vertico-child-frame-poshandler-other-window-center`
- `other-window-top-center` / `vertico-child-frame-poshandler-other-window-top-center`
- `other-window-top-left-corner` / `vertico-child-frame-poshandler-other-window-top-left-corner`
- `other-window-top-right-corner` / `vertico-child-frame-poshandler-other-window-top-right-corner`
- `other-window-bottom-center` / `vertico-child-frame-poshandler-other-window-bottom-center`
- `other-window-bottom-left-corner` / `vertico-child-frame-poshandler-other-window-bottom-left-corner`
- `other-window-bottom-right-corner` / `vertico-child-frame-poshandler-other-window-bottom-right-corner`

### Point / Cursor-relative

- `point-bottom-left-corner` / `vertico-child-frame-poshandler-point-bottom-left-corner` — below point, automatically flipping above point when near the bottom edge
- `point-top-left-corner` / `vertico-child-frame-poshandler-point-top-left-corner` — top-left aligned to point
- `point-bottom-left-corner-upward` / `vertico-child-frame-poshandler-point-bottom-left-corner-upward` — placed above point
- `point-window-center` / `vertico-child-frame-poshandler-point-window-center` — horizontally centered in active window, vertically anchored at point
- `point-frame-center` / `vertico-child-frame-poshandler-point-frame-center` — horizontally centered in parent frame, vertically anchored at point

All coordinates apply `vertico-child-frame-offset` plus recursive cascade offsets and are clamped within `vertico-child-frame-margin` inside the parent frame.

## Customization Options & Faces

### Options

| Option | Default | Description |
| --- | --- | --- |
| `vertico-child-frame-width` | `0.6` | `nil` (default `0.6`), float fraction of parent width, column integer, or `(fn parent)` |
| `vertico-child-frame-min-width` | `50` | Minimum width in columns, float fraction, or `nil` |
| `vertico-child-frame-max-width` | `120` | Maximum width in columns, float fraction, or `nil` |
| `vertico-child-frame-height` | `nil` | `nil` (auto via `vertico-count`/`resize`), line integer, float fraction, or `(fn parent lines)` |
| `vertico-child-frame-resize` | `nil` | `nil` (fixed), `t` (grow & shrink), or `grow-only` (when `height` is `nil`) |
| `vertico-child-frame-min-height` | `nil` | Minimum height in lines, float fraction, or `nil` (1 line) |
| `vertico-child-frame-max-height` | `0.5` | Maximum height as float fraction of parent height, line integer, or `nil` |
| `vertico-child-frame-poshandler` | `#'vertico-child-frame-poshandler-frame-top-center` | Position handler function or short symbol |
| `vertico-child-frame-offset` | `'(0 . 0)` | Additional pixel offset `(DX . DY)` added after poshandler |
| `vertico-child-frame-top-offset` | `nil` | Top offset (`nil` uses vertical `margin`, or fraction / pixels) |
| `vertico-child-frame-bottom-offset` | `nil` | Bottom offset (`nil` uses vertical `margin`, or fraction / pixels) |
| `vertico-child-frame-margin` | `'(16 . 16)` | Edge margin `(x . y)` in pixels |
| `vertico-child-frame-recursive-offset` | `'(24 . 24)` | Cascade offset `(dx . dy)` per recursive level |
| `vertico-child-frame-font` | `nil` | Explicit font string for the child frame, or `nil` to inherit |
| `vertico-child-frame-alpha` | `nil` | Background opacity integer (0–100) or `(ACTIVE . INACTIVE)` cons |
| `vertico-child-frame-border-width` | `1` | Child-frame border width in pixels |
| `vertico-child-frame-internal-border-width` | `0` | Internal border (inner padding) in pixels |
| `vertico-child-frame-left-fringe` | `8` | Left fringe width in pixels |
| `vertico-child-frame-right-fringe` | `8` | Right fringe width in pixels |
| `vertico-child-frame-mode-line-format` | `nil` | `mode-line-format` inside the child frame |
| `vertico-child-frame-header-line-format` | `nil` | `header-line-format` inside the child frame |
| `vertico-child-frame-hide-minibuffer` | `t` | Hide prompt inside parent minibuffer window |
| `vertico-child-frame-truncate-lines` | `'auto` | `'auto` (auto-wrap long input), `nil` (always wrap), or `t` (always truncate) |
| `vertico-child-frame-min-parent-width` | `40` | Minimum parent frame columns |
| `vertico-child-frame-min-parent-height` | `10` | Minimum parent frame rows |
| `vertico-child-frame-fallback-mode` | `nil` | Optional fallback Vertico mode for TTY / small frames |
| `vertico-child-frame-parameters` | `nil` | Extra frame parameters merged at frame creation |

### Faces

| Face | Description |
| --- | --- |
| `vertico-child-frame` | Background, foreground, and font of the child frame (inherits `default`) |
| `vertico-child-frame-border` | Background specifies the child-frame border color |

### Commands

- `vertico-child-frame-mode` — global minor mode
- `vertico-child-frame-set-poshandler` — interactively select and apply a built-in poshandler
- `vertico-child-frame-cleanup` — delete all pooled child frames
- `vertico-multiform-child-frame` — toggle child-frame display inside the active minibuffer

## Development & Testing

Run byte-compilation (`byte-compile-error-on-warn t`), `checkdoc` lint, and ERT tests:

```bash
make check
```

To test against an actual local checkout of `vertico`:

```bash
VERTICO_DIR=/path/to/vertico make test
```

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
