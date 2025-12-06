@visualization @grid
Feature: Grid Display
  As a user
  I want to display reference grids
  So that I can understand the model's scale and orientation

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Default grid mode is off
    When a model is first loaded
    Then the grid display should be off

  Scenario: Cycle grid mode with keyboard
    When I press Cmd+G
    Then the grid mode should cycle to the next mode
    And the cycle should include all available grid modes

  Scenario: Grid mode "Bottom"
    When I set grid mode to "Bottom"
    Then a grid should be displayed on the XZ plane
    And the grid should be positioned at the model's bottom
    And the grid should show dimension labels

  Scenario: Grid mode "All Sides"
    When I set grid mode to "All Sides"
    Then grids should be displayed on all 6 faces of the bounding box
    And each grid should show appropriate dimension labels

  Scenario: Grid mode "1mm Grid"
    When I set grid mode to "1mm Grid"
    Then a fine 1mm spacing grid should be displayed
    And this allows for precision work and measurements

  Scenario: Grid labels display dimensions
    When any grid mode is active
    Then dimension labels should be displayed as text billboards
    And the labels should show the size in appropriate units

  Scenario: Grid adaptive sizing
    When any grid mode is active
    Then the grid should automatically adjust to model bounds
    And the grid size should encompass the entire model

  Scenario: Select grid mode from menu
    When I open the View menu
    And I navigate to the Grid submenu
    Then I should see options for "Off", "Bottom", "All Sides", and "1mm Grid"
    When I select an option
    Then the grid mode should change accordingly
