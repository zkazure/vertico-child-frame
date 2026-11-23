# vertico-child-frame

Display [Vertico](https://github.com/minad/vertico) in a native Emacs child frame — with zero external dependencies beyond `vertico` itself.

## Why `vertico-child-frame`?

Existing child-frame extensions for Vertico (`vertico-posframe` and `vertico-buffer-frame`) suffer from frame recreation overhead, compositor flicker, broken recursive minibuffer stacking, long-path jitter, or misaligned annotations. `vertico-child-frame` is built directly on Emacs 29/30+ native child-frame primitives to solve these cleanly:

| Feature | `vertico-child-frame` | `vertico-posframe` | `vertico-buffer-frame` |
| --- | --- | --- | --- |
| External dependencies | None (only `vertico`) | `posframe` | None (wraps `vertico-buffer`) |
| Frame reuse | Per-depth frame pool | Single `posframe` buffer/frame | `display-buffer-in-child-frame` |
| Geometry caching | Skips no-op move/resize calls | Re-evaluates per update | Re-evaluates via `display-buffer` |
| Recursive minibuffers | Depth-indexed pool + cascade offset + outer re-raise | Overlapping / focus quirks | Window layout interference |
| Long-path stability | `truncate-lines`, `auto-hscroll-mode 'current-line`, `resize-mini-windows nil` | Known `C-x C-f` jitter & clipping | Inherits buffer window wrapping |
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

### `vertico-multiform` integration (recommended for mixed layouts)

`vertico-child-frame` registers `vertico-child-frame-mode` in `vertico-multiform--display-modes` and defines `vertico-multiform-child-frame` (bound to `M-C` in `vertico-multiform-map` if unbound).

Do **not** enable `(vertico-child-frame-mode 1)` globally if you want `vertico-multiform-mode` to control it per command or category:

```elisp
(require 'vertico-child-frame)
(require 'vertico-multiform)

(setq vertico-multiform-commands
      '((consult-line buffer)
        (consult-ripgrep buffer)
        (t child-frame)))

(vertico-multiform-mode 1)
```

### `consult` and `embark`

- **Consult live previews**: The default `vertico-child-frame-poshandler-top-center` keeps the middle and lower portions of your frame visible so live buffer/file previews remain readable.
- **Embark recursive actions**: Recursive minibuffers (`enable-recursive-minibuffers t`) each receive their own pooled child frame for their `(minibuffer-depth)`, shifted by `vertico-child-frame-recursive-offset` (default `(24 . 24)` pixels). Exiting the inner prompt hides the nested frame and re-raises the outer session's frame automatically.

### TTY / small-frame fallback

When running in a terminal (`emacs -nw`) without child-frame support or when the parent frame is smaller than `vertico-child-frame-min-parent-width` / `vertico-child-frame-min-parent-height`, `vertico-child-frame` automatically steps aside and optionally enables `vertico-child-frame-fallback-mode` for the duration of that session:

```elisp
(setq vertico-child-frame-fallback-mode #'vertico-buffer-mode)
```

Leave `vertico-child-frame-fallback-mode` as `nil` to fall back to the standard bottom minibuffer.

## Poshandlers

Set `vertico-child-frame-poshandler` to any of the built-in functions or a custom `(lambda (parent width height) (cons x y))` returning pixel coordinates relative to `parent`:

- `vertico-child-frame-poshandler-top-center` *(default)* — horizontally centered at `vertico-child-frame-top-offset` (`0.12`)
- `vertico-child-frame-poshandler-center` — dead center of the parent frame
- `vertico-child-frame-poshandler-bottom-center` — horizontally centered near the bottom (`vertico-child-frame-bottom-offset`)
- `vertico-child-frame-poshandler-window-top-center` — top-center of `(minibuffer-selected-window)`
- `vertico-child-frame-poshandler-window-center` — center of `(minibuffer-selected-window)`

All coordinates are automatically clamped within `vertico-child-frame-margin` inside the parent frame.

## Customization Options & Faces

### Options

| Option | Default | Description |
| --- | --- | --- |
| `vertico-child-frame-width` | `0.6` | Float fraction of parent width, column integer, or `(fn parent)` |
| `vertico-child-frame-min-width` | `50` | Minimum width in columns (`nil` for none) |
| `vertico-child-frame-max-width` | `120` | Maximum width in columns (`nil` for none) |
| `vertico-child-frame-resize` | `nil` | `nil` (fixed), `t` (grow & shrink), or `grow-only` |
| `vertico-child-frame-min-height` | `nil` | Minimum height in lines (`nil` for 1) |
| `vertico-child-frame-max-height` | `0.5` | Float fraction of parent height or max lines |
| `vertico-child-frame-poshandler` | `#'vertico-child-frame-poshandler-top-center` | Position calculator function |
| `vertico-child-frame-top-offset` | `0.12` | Top offset (fraction or pixels) |
| `vertico-child-frame-bottom-offset` | `0.06` | Bottom offset (fraction or pixels) |
| `vertico-child-frame-margin` | `'(16 . 16)` | Edge margin `(x . y)` in pixels |
| `vertico-child-frame-recursive-offset` | `'(24 . 24)` | Cascade offset `(dx . dy)` per recursive level |
| `vertico-child-frame-border-width` | `1` | Child-frame border width in pixels |
| `vertico-child-frame-internal-border-width` | `0` | Internal border (padding) in pixels |
| `vertico-child-frame-left-fringe` | `8` | Left fringe width in pixels |
| `vertico-child-frame-right-fringe` | `8` | Right fringe width in pixels |
| `vertico-child-frame-hide-minibuffer` | `t` | Hide prompt inside parent minibuffer window |
| `vertico-child-frame-truncate-lines` | `t` | Truncate long lines inside the child frame |
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
