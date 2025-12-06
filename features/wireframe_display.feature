@visualization @wireframe
Feature: Wireframe Display Modes
  As a user
  I want to toggle wireframe display modes
  So that I can see the mesh structure and identify features

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Default wireframe mode is off
    When a model is first loaded
    Then the wireframe display should be off
    And only the solid surface should be visible

  Scenario: Cycle wireframe mode with keyboard
    When I press Cmd+W
    Then the wireframe mode should cycle to the next mode
    And the cycle order should be: Off -> All -> Edge -> Off

  Scenario: Wireframe mode "All"
    When I set wireframe mode to "All"
    Then all triangle edges should be displayed
    And the wireframe should overlay the solid surface

  Scenario: Wireframe mode "Edge"
    When I set wireframe mode to "Edge"
    Then edges should be displayed with angle-based styling
    And feature edges (>= 20 degrees) should be displayed at full width and opacity
    And soft edges (1-20 degrees) should be displayed at half width and 30% opacity
    And edges below 1 degree should be hidden
    And boundary edges (single adjacent face) should always be displayed as feature edges

  Scenario: Edge mode angle thresholds
    Given wireframe mode is set to "Edge"
    Then the feature edge threshold should be 20 degrees
    And the minimum visible edge threshold should be 1 degree
    And these thresholds ensure a clean visualization that highlights model features

  Scenario: Wireframe thickness auto-scaling
    When wireframe is enabled
    Then the wireframe line thickness should be 0.2% of the model diagonal
    And this ensures consistent visibility across different model sizes

  Scenario: Select wireframe mode from menu
    When I open the View menu
    And I navigate to the Wireframe submenu
    Then I should see options for "Off", "All", and "Edge"
    When I select an option
    Then the wireframe mode should change accordingly
