# Ra Curved Bars

Ra Curved Bars is a player status-bar addon for the Project Rubi-Ka Spiritech client.

## Install in Spiritech

1. Get the `Ra_curved_bars` folder from a shared ZIP. If you have access to the GitHub repository, use **Code → Download ZIP**, extract it, and rename `Ra_curved_bars-main` to `Ra_curved_bars`.
2. Close Spiritech. In your PRK installation, open `client\UI\Addons` and create the `Addons` folder if needed.
3. Copy the entire `Ra_curved_bars` folder into `Addons`. Check that `package.xml` ends up here.

   ```text
   <PRK installation>\client\UI\Addons\Ra_curved_bars\package.xml
   ```

4. Start Spiritech. On the sign-in screen, press **F10** and search for **Player status bars**. You can also find the setting under **Interface & HUD → UI packages**.
5. Open the **Player status bars** dropdown, select **Ra Curved Bars**, and click **Apply**.
6. Enter the game and hover over Health or Nano to check that the bar shows its current and maximum values. If you applied the setting while already in game, return to character selection and press **Play** first.

If **Ra Curved Bars** is missing from the dropdown, check the folder path in step 3 and restart Spiritech. If the addon is selected and a bar is hidden, open **Actions → Status Bars** in the Control Center and select the bar you want to show.

## Use Ra Curved Bars

By default, the red Health bar bows left and the blue Nano bar bows right, with their maximum at the top and zero at the bottom. Gold XP/SK and green Alien XP use the same design at 75% scale and start near Health and Nano, respectively. All bars fill upward with a smooth black outline and nine horizontal marks at 10% intervals. Hover over any bar to see its current and maximum values.

Each pair has its own snap targets. When both bars in a pair are visible, dragging slows near the other bar's height and its mirrored position across the screen's centerline. Release close to either point to snap exactly into place. Each direction snaps independently, and dragging farther lets you place the bar freely.

Right-click a visible bar to open its menu. Choose **Straight** or **Curved** for its shape and **Horizontal** or **Vertical** for its orientation. Choose **Curved** again to flip the curve. Each bar saves its own choices for the current character. Horizontal Health and Nano fill from right to left, with the maximum on the left. Horizontal XP bars fill from left to right, and vertical bars fill upward.

Choose **Lock in place** or **Unlock** for the selected bar. The menu offers **Lock all** when bars can be locked and **Unlock all** when bars can be unlocked. These actions include hidden bars. Click outside the menu to dismiss it. Lock settings are saved for the current character.

## License

Original Ra Curved Bars contributions are available under the [MIT License](LICENSE). Upstream material from the Spiritech Status Bars package retains its own terms.
