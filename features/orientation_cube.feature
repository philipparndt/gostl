@camera @orientation-cube
Feature: Orientation Cube
  As a user
  I want an interactive orientation cube
  So that I can quickly navigate to standard views and understand my current orientation

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Orientation cube display
    Then an orientation cube should be visible in the top-right corner
    And the cube should be displayed in a 300x300 pixel viewport
    And the cube should have a 20 pixel margin from the edge

  Scenario: Cube rotation matches camera
    When I rotate the camera
    Then the orientation cube should rotate to match the camera orientation
    And the cube faces should show the correct orientation labels

  Scenario: Click cube face to change view
    When I click on a face of the orientation cube
    Then the camera should jump to that view
    And the view transition should be smooth

  Scenario: Click X axis label
    When I click on the X axis label of the orientation cube
    Then the camera should constrain to the X axis view

  Scenario: Click Y axis label
    When I click on the Y axis label of the orientation cube
    Then the camera should constrain to the Y axis view

  Scenario: Click Z axis label
    When I click on the Z axis label of the orientation cube
    Then the camera should constrain to the Z axis view

  Scenario: Hover effect on cube faces
    When I hover over a face of the orientation cube
    Then the face should show a visual hover effect
    And this should indicate the face is clickable

  Scenario: Arrow tips on axes
    Then each axis of the orientation cube should have an arrow tip
    And the arrows should indicate the positive direction of each axis
