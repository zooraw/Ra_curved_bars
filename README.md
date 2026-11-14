# Ra Curved Bars

Spiritech player status-bar provider. The red Health bar bows left and the blue Nano bar bows right, with their maximum at the top and zero at the bottom. Gold XP/SK and green Alien XP use the same design at 75% scale and start near Health and Nano, respectively. All bars fill upward with a smooth black outline and nine horizontal marks at 10% intervals. Hover over any bar to see its current and maximum values.

Each pair has its own snap targets. When both bars in a pair are visible, dragging slows near the other bar's height and its mirrored position across the screen's centerline. Release close to either point to snap exactly into place. Each direction snaps independently, and dragging farther lets you place the bar freely.

Right-click the visible curve to open its position menu at the pointer. Choose **Lock in place** or **Unlock** for that bar. The menu offers **Lock all** when bars can be locked and **Unlock all** when bars can be unlocked. These actions include hidden bars. Click outside the menu to dismiss it. Lock settings are saved for the current character.

1. Copy `Ra_curved_bars` into the client’s `UI/Addons` directory if it is not installed there yet. Restart Spiritech so it can discover the package.
2. Open **F10 → Interface & HUD → UI packages**. Select **Ra Curved Bars** for **Player status bars** and click **Apply**.
3. Start a new character session. If a bar is hidden, open **Actions → Status Bars** and select **Health** or **Nano** in the Control Center.
