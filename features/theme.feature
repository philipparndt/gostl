@ui @theme
Feature: Theme Selection
  As a user
  I want to choose between dark and light themes
  So that the viewer matches my preferred working environment

  Background:
    Given the application is running

  Scenario: Default theme on first launch
    Given the user has never selected a theme
    Then the app should start with the dark theme
    And the 3D viewport background should be the dark theme background color

  Scenario: Theme selection menu
    When I open the View menu
    Then I should see a "Theme" picker
    And the picker should offer "Dark" and "Light" options
    And the currently active theme should be indicated

  Scenario: Switch to light theme
    Given the dark theme is active
    When I select "Light" from the View > Theme picker
    Then the 3D viewport background should switch to the light theme background
    And grid lines should remain visible against the light background
    And dimension labels should remain readable
    And the build plate (if shown) should redraw with light-theme colors
    And SwiftUI overlays should adopt the light color scheme

  Scenario: Switch back to dark theme
    Given the light theme is active
    When I select "Dark" from the View > Theme picker
    Then the 3D viewport background should switch to the dark theme background
    And all overlays and panels should adopt the dark color scheme

  Scenario: Theme persists across app launches
    Given I have selected the light theme
    When I quit and relaunch the application
    Then the application should start with the light theme

  Scenario: Theme applies to all open windows
    Given two GoSTL windows are open
    When I change the theme in one window
    Then both windows should update to the new theme

  Scenario: Material colors are independent of theme
    Given a model is loaded with a selected material
    When I switch between dark and light themes
    Then the material color (PLA, ABS, PETG, TPU, Nylon) should remain unchanged
    And measurement colors and axis colors should remain unchanged
