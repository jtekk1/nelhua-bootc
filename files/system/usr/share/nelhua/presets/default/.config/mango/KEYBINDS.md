# Keybindings Reference

Generated 2026-04-10. Covers mango (WM) and kitty (terminal) keybindings.

## Design Philosophy

- **`SUPER,<key>`** — pure WM control (window state, focus, tags, system)
- **`SUPER+SHIFT,<key>`** — native apps (TUIs launch in foot, nvim in kitty)
- **`SUPER+ALT,<key>`** — webapps and layout adjustment
- **`SUPER+CTRL,<key>`** — layouts, reload, gaps, locks

---

## SUPER — WM control

### Window state
| Key | Action |
|---|---|
| `SUPER,w` | Kill window |
| `SUPER,a` | Toggle maximize |
| `SUPER,s` | Zoom (swap with master) |
| `SUPER,i` | Minimize |
| `SUPER,g` | Toggle global (show on all tags) |
| `SUPER,\` | Toggle floating |
| `SUPER,minus` | Toggle scratchpad |

### Focus & motion
| Key | Action |
|---|---|
| `SUPER,←/→/↑/↓` | Focus window in direction |
| `SUPER,Tab` | Focus next window in stack |
| `SUPER,u` | Focus last window |
| `Alt,Tab` | Toggle overview |

### Tags (workspaces)
| Key | Action |
|---|---|
| `SUPER,1..9` | View tag N |
| `SUPER+SHIFT,1..9` | Move window to tag N |
| `SUPER+CTRL,1..9` | Toggle tag N into view |
| `SUPER+CTRL+SHIFT,1..9` | Assign to tag silently |
| `SUPER+ALT,1..9` | Toggle window on tag N |

### System
| Key | Action |
|---|---|
| `SUPER,Return` | kitty (regular terminal) |
| `SUPER+SHIFT,Return` | foot (themed terminal) |
| `SUPER,space` | wofi drun launcher |
| `SUPER,v` | wofi clipboard menu |
| `SUPER,Escape` | Power menu (wlogout) |
| `SUPER,backspace` | Toggle notification center |
| `SUPER+SHIFT,backspace` | Clear notifications |
| `SUPER,slash` | Bitwarden |

---

## SUPER+SHIFT — Native apps

| Key | App | Runs in |
|---|---|---|
| `SUPER+SHIFT,b` | btop | foot |
| `SUPER+SHIFT,f` | yazi | foot |
| `SUPER+SHIFT,h` | htop | foot |
| `SUPER+SHIFT,i` | impala (wifi) | foot |
| `SUPER+SHIFT,l` | lazygit | foot |
| `SUPER+SHIFT,m` | spotify | — |
| `SUPER+SHIFT,n` | nvim | **kitty** |
| `SUPER+SHIFT,p` | spf | foot |
| `SUPER+SHIFT,t` | helium (browser) | — |
| `SUPER+SHIFT,u` | bluetui | foot |
| `SUPER+SHIFT,x` | claude | foot |

### Also on SUPER+SHIFT
| Key | Action |
|---|---|
| `SUPER+SHIFT,←/→/↑/↓` | Swap window with neighbor |
| `SUPER+SHIFT,e` | Set scroller proportion to 0.33 |

---

## SUPER+ALT — Webapps & layout adjustment

### Webapps (chromium --app=)
| Key | Webapp |
|---|---|
| `SUPER+ALT,a` | audible |
| `SUPER+ALT,d` | discord |
| `SUPER+ALT,g` | gemini |
| `SUPER+ALT,n` | netflix |
| `SUPER+ALT,u` | upwork |
| `SUPER+ALT,y` | youtube |

### Master/stack control
| Key | Action |
|---|---|
| `SUPER+ALT,e` | Increment master count (+1) |
| `SUPER+ALT,t` | Decrement master count (−1) |
| `SUPER+ALT,h` | Shrink master area (setmfact −0.05) |
| `SUPER+ALT,l` | Grow master area (setmfact +0.05) |
| `SUPER+ALT,x` | Cycle scroller proportion preset |

### Scroller layout
| Key | Action |
|---|---|
| `SUPER+ALT,←/→/↑/↓` | Scroller stack in direction |

### Window states
| Key | Action |
|---|---|
| `SUPER+ALT,f` | Toggle fake fullscreen |
| `SUPER+ALT,o` | Toggle overlay |
| `SUPER+ALT,i` | Restore minimized windows |

### Monitor & misc
| Key | Action |
|---|---|
| `SUPER+ALT+SHIFT,←/→/↑/↓` | Move window to monitor |
| `SUPER+ALT,b` | Restart waybar |
| `SUPER+ALT,w` | Next wallpaper |
| `SUPER+ALT,p` | Previous wallpaper |
| `SUPER+ALT+SHIFT,w` | Random wallpaper |
| `CTRL+ALT+SHIFT,t` | Time-based wallpaper |

---

## SUPER+CTRL — Layouts, gaps, system

### Layout switchers (via osd-mango)
| Key | Layout |
|---|---|
| `SUPER+CTRL,t` | tiling |
| `SUPER+CTRL,x` | tgmix |
| `SUPER+CTRL,s` | scrolling |
| `SUPER+CTRL,m` | monocle |
| `SUPER+CTRL,g` | grid |
| `SUPER+CTRL,d` | deck |
| `SUPER+CTRL,c` | centerTiling |
| `SUPER+CTRL,e` | verticalScrolling |
| `SUPER+CTRL,v` | verticalTiling |

### Gaps
| Key | Action |
|---|---|
| `SUPER+CTRL,=` | Increase gaps (+10) |
| `SUPER+CTRL,-` | Decrease gaps (−10) |
| `SUPER+CTRL,0` | Toggle gaps |

### System & workspaces
| Key | Action |
|---|---|
| `SUPER+CTRL,r` | Reload mango config |
| `SUPER+CTRL,l` | Toggle sunset (dim lights) |
| `SUPER+CTRL,w` | wofi wallpaper switcher |
| `SUPER+CTRL,Escape` | Lock screen (swaylock) |
| `SUPER+CTRL,←/→` | Previous / next workspace (view) |
| `SUPER+CTRL+SHIFT,←/→` | Move tag to previous / next workspace |
| `SUPER+CTRL+ALT,Escape` | **Quit mango** |

---

## Unmodified keys

### Media & brightness
| Key | Action |
|---|---|
| `XF86AudioRaiseVolume` | Volume +5% |
| `XF86AudioLowerVolume` | Volume −5% |
| `XF86AudioMute` | Toggle mute |
| `XF86AudioPlay` | Play/pause |
| `XF86AudioStop` | Stop |
| `XF86AudioNext` | Next track |
| `XF86AudioPrev` | Previous track |
| `XF86MonBrightnessUp` | Brightness +5% |
| `XF86MonBrightnessDown` | Brightness −5% |

### Screenshots
| Key | Action |
|---|---|
| `Print` | Screenshot full screen → `~/Pictures/` |
| `CTRL+ALT,4` | Full screen → clipboard |
| `CTRL+SHIFT,4` | Area screenshot → clipboard |
| `CTRL+ALT,a` | Area screenshot → satty editor |

### Other
| Key | Action |
|---|---|
| `CTRL+SHIFT,space` | Nerd fonts cheat sheet (chromium app) |

---

## Mouse & gestures

### Mouse (hold SUPER)
| Button | Action |
|---|---|
| `SUPER+Left click` | Move window |
| `SUPER+Right click` | Resize window |
| `SUPER+Middle click` | Toggle floating |

### Touchpad gestures
| Gesture | Action |
|---|---|
| 3-finger ←/→/↑/↓ | Focus direction |
| 4-finger ←/→ | Workspace prev/next |
| 4-finger ↑/↓ | Toggle overview |

### Smart move & resize
| Key | Action |
|---|---|
| `CTRL+SHIFT,←/→/↑/↓` | Smart move window |
| `CTRL+ALT,←/→/↑/↓` | Smart resize window |

---

## Kitty terminal

Configured with `splits` layout. Uses Alt for split navigation (doesn't conflict with mango's SUPER-based binds).

### Splits
| Key | Action |
|---|---|
| `alt+d` | New vertical split |
| `alt+shift+d` | New horizontal split |
| `alt+enter` | New split in current working directory |
| `ctrl+shift+w` | Close split |

### Focus between splits
| Key | Action |
|---|---|
| `alt+h` | Focus split left |
| `alt+l` | Focus split right |
| `alt+k` | Focus split up |
| `alt+j` | Focus split down |

### Resize splits
| Key | Action |
|---|---|
| `alt+shift+h` | Narrower |
| `alt+shift+l` | Wider |
| `alt+shift+k` | Taller |
| `alt+shift+j` | Shorter |

---

## Removed bindings (reference)

These used to exist and have been intentionally removed:

- `SUPER,b/c/f/h/l/m/n/o/t/x` — native apps moved to `SUPER+SHIFT,<letter>`
- `SUPER,c` — cursor (no longer used)
- `SUPER,o` — obsidian (no longer used)
- `SUPER,q` — kill window (now `SUPER,w`)
- `SUPER,r` — wofi run (use `SUPER,space` drun instead)
- `ALT,f` — togglefullscreen (use `SUPER,a` maximize or `SUPER+ALT,f` fake fullscreen)
- `SUPER+SHIFT,a/d/g/h/i/m/n/o/u/y` — webapps moved to `SUPER+ALT,<letter>`
- `SUPER+SHIFT,b` — toggle-waybar (removed entirely)
- `SUPER+SHIFT,c` — chromium launcher (rely on wofi drun)
- `SUPER+SHIFT,h` — HBO Max webapp
- `SUPER+SHIFT,i` — Instagram webapp
- `SUPER+SHIFT,m` — Mail webapp
- `SUPER+SHIFT,o` — ChatGPT webapp
- `SUPER+CTRL,n` — impala (moved to `SUPER+SHIFT,i`)
- `SUPER+ALT,m` — quit mango (moved to `SUPER+CTRL+ALT,Escape`)
- `SUPER+ALT,n` — switch_layout cycle (removed; use specific layout binds)
- `CTRL,←/→` — workspace nav (was hijacking word-motion in text fields)
