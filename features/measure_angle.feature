@measurement @angle
Feature: Angle Measurement
  As a user
  I want to measure angles between surfaces
  So that I can verify geometric relationships

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Start angle measurement mode
    When I press Cmd+A
    Then angle measurement mode should be activated
    And the cursor should indicate measurement mode is active

  Scenario: Three-point angle measurement
    Given angle measurement mode is active
    When I click the first point on the model
    And I click the second point on the model (the vertex)
    And I click the third point on the model
    Then the angle at the middle point should be calculated
    And the angle value should be displayed

  Scenario: Angle display format
    Given I have completed an angle measurement
    Then the angle should be displayed in degrees
    And the angle should be formatted to 1 decimal place
    And the label should be positioned at the vertex point

  Scenario: Cancel angle measurement
    Given angle measurement mode is active
    And I have placed fewer than 3 points
    When I press Escape
    Then the angle measurement should be cancelled
    And any placed points should be removed
