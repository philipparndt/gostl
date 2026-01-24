@ui @menus
Feature: Application Menus
  As a user
  I want organized menus
  So that I can access all features through the menu bar

  Background:
    Given the application is running

  Scenario: File menu structure
    When I open the File menu
    Then I should see "New Tab" with shortcut Cmd+T
    And I should see "Open..." with shortcut Cmd+O
    And I should see "Open Recent" as a submenu
    And "Open Recent" should have "Clear Menu" option
    And I should see "Reload" with shortcut Cmd+R

  Scenario: View menu structure
    When I open the View menu
    Then I should see "Info Panel" toggle with Cmd+I
    And I should see "Wireframe" submenu with Off/All/Edge options
    And I should see "Cycle Wireframe Mode" with Cmd+W
    And I should see "Grid" submenu with Off/Bottom/All Sides/1mm Grid options
    And I should see "Cycle Grid Mode" with Cmd+G
    And I should see "Build Plate" submenu with printer options
    And I should see "Cycle Build Plate" with Cmd+B
    And I should see "Slicing" toggle with Cmd+Shift+S
    And I should see "Show Diameter" toggle for radius measurements
    And I should see "Camera" submenu with view presets

  Scenario: Camera submenu
    When I open the View menu
    And I navigate to the Camera submenu
    Then I should see "Front" with Cmd+1
    And I should see "Back" with Cmd+2
    And I should see "Left" with Cmd+3
    And I should see "Right" with Cmd+4
    And I should see "Top" with Cmd+5
    And I should see "Bottom" with Cmd+6
    And I should see "Reset View" with Cmd+0

  Scenario: Tools menu structure
    When I open the Tools menu
    Then I should see "Measure Distance" with Cmd+D
    And I should see "Measure Angle" with Cmd+A
    And I should see "Measure Radius"
    And I should see "Select Triangles" with T
    And I should see "Clear All Measurements" with Cmd+Shift+K
    And I should see "Copy as OpenSCAD" with Cmd+Shift+C
    And I should see "Change Material" with Cmd+M
    And I should see "Open with go3mf"

  Scenario: Help menu structure
    When I open the Help menu
    Then I should see "About GoSTL"
    And selecting it should show version info, build date, and commit hash
