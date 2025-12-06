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
    Then only feature edges should be displayed
    And feature edges are edges where adjacent faces exceed the angle threshold
    And non-feature edges should be hidden

  Scenario: Configure edge angle threshold
    Given wireframe mode is set to "Edge"
    When I adjust the edge angle threshold
    Then the threshold should be adjustable from 1 to 90 degrees
    And the default threshold should be 30 degrees
    And the wireframe should update to show edges exceeding the new threshold

  Scenario: Debounced threshold slider
    Given wireframe mode is set to "Edge"
    When I rapidly adjust the angle threshold slider
    Then the wireframe should update with a 150ms debounce delay
    And this ensures responsive UI during adjustment

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
