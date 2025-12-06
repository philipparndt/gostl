@file-handling @auto-reload
Feature: Auto-Reload on File Changes
  As a user
  I want the application to automatically reload when source files change
  So that I can see updates without manually reopening files

  Background:
    Given the application is running
    And I have a 3D model file open

  Scenario: Auto-reload on file modification
    When the currently open file is modified externally
    Then the file should be automatically reloaded
    And the updated 3D model should be displayed
    And the camera position should be preserved

  Scenario: Debounce rapid file changes
    When the file is modified multiple times within 1.5 seconds
    Then only one reload should occur
    And the reload should happen after the debounce period

  @openscad
  Scenario: Auto-reload OpenSCAD with dependencies
    Given I have an OpenSCAD file open
    And the OpenSCAD file includes other files
    When any included file is modified
    Then the main file should be re-rendered
    And the updated model should be displayed

  @go3mf
  Scenario: Auto-reload go3mf with dependencies
    Given I have a go3mf YAML file open
    And the YAML file references other files
    When any referenced file is modified
    Then the configuration should be re-rendered
    And the updated model should be displayed

  Scenario: Preserve camera on reload
    Given I have positioned the camera at a specific angle
    When the file is auto-reloaded
    Then the camera position should remain unchanged
    And the camera orientation should remain unchanged

  Scenario: Preserve material selection on reload
    Given I have selected a specific material
    When the file is auto-reloaded
    Then the selected material should remain unchanged
    And the weight calculation should use the preserved material

  Scenario: Error overlay on reload failure
    When the file is modified and causes a render error
    Then an error overlay should appear at the bottom
    And the error details should be displayed
    And the previous model should remain visible
    And the overlay should be dismissible with a close button
    And the overlay should disappear on the next successful reload

  Scenario: Cooldown period between reloads
    When a reload completes
    Then no new reload should occur for at least 1.5 seconds
    And this prevents rapid re-triggers during file saves

  Scenario: File watcher pause during reload
    When a reload is in progress
    Then the file watcher should be paused
    And this prevents recursive reload triggers
    And the watcher should resume after reload completes
