# Integration Notes

This is the short version of the manual setup notes.

## Bar button

Add an `ai` entry to `config/BarConfig.qml`:

```qml
{
    id: "ai",
    enabled: true
},
```

Add a delegate to `modules/bar/Bar.qml`:

```qml
DelegateChoice {
    roleValue: "ai"
    delegate: WrappedLoader {
        sourceComponent: Ai {}
    }
}
```

The bar icon component lives at:

```text
modules/bar/components/Ai.qml
```

## Popout

Register the popout in `modules/bar/popouts/Content.qml`:

```qml
Popout {
    name: "ai"
    sourceComponent: Ai {
        popouts: root.popouts
    }
}
```

The popout itself lives at:

```text
modules/bar/popouts/Ai.qml
```

## Center blob

The center prompt window uses:

```text
modules/blob/Content.qml
modules/blob/Wrapper.qml
modules/BlobIpc.qml
```

`BlobIpc.qml` watches `~/.local/state/caelestia/blob-trigger`.
The `caelestia-blob` command writes that trigger file.

## Drawers

The center blob requires:

- `components/DrawerVisibilities.qml` with `property bool blob`
- `modules/drawers/Drawers.qml` focus handling for `visibilities.blob`
- `modules/drawers/Panels.qml` importing and placing `Blob.Wrapper`
