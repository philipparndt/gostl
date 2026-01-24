@measurement @radius
Feature: Radius Measurement
  As a user
  I want to measure radii of circular features
  So that I can verify hole and curve dimensions

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Start radius measurement from menu
    When I select "Measure Radius" from the Tools menu
    Then radius measurement mode should be activated
    And the cursor should indicate measurement mode is active

  Scenario: Start radius measurement with keyboard
    When I press R (while not in distance mode)
    Then radius measurement mode should be activated

  Scenario: Three-point circle fitting
    Given radius measurement mode is active
    When I click three points on a circular feature
    Then a least-squares circle should be fitted to the points
    And the circle radius should be calculated
    And the circle center should be determined

  Scenario: Radius display
    Given I have completed a radius measurement
    Then the radius value should be displayed
    And the value should be shown with auto-scaling precision
    And a circle center point should be indicated

  Scenario: Cancel radius measurement
    Given radius measurement mode is active
    And I have placed fewer than 3 points
    When I press Escape
    Then the radius measurement should be cancelled
    And any placed points should be removed

  Scenario: Toggle diameter display via menu
    Given I have completed a radius measurement
    When I enable "Show Diameter" in the View menu
    Then the radius measurements should display as diameter
    And the label should be prefixed with "d:"
    And the displayed value should be double the radius
    When I disable "Show Diameter" in the View menu
    Then the measurements should display as radius again
    And the label should be prefixed with "r:"
