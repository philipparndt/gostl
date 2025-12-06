@ui @info-panel
Feature: Model Information Panel
  As a user
  I want to see detailed information about the loaded model
  So that I can understand its properties and dimensions

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Toggle info panel visibility
    When I press Cmd+I
    Then the info panel visibility should toggle
    And the panel should appear at the top-left of the screen

  Scenario: Toggle info panel from menu
    When I select "Info Panel" from the View menu
    Then the info panel visibility should toggle

  Scenario: File information display
    When the info panel is visible
    Then I should see the filename in monospaced font
    And I should see the triangle count with thousands separator
    And I should see a slicing indicator when slicing is active

  Scenario: Model dimensions display
    When the info panel is visible
    Then I should see Width (X axis dimension)
    And I should see Height (Y axis dimension)
    And I should see Depth (Z axis dimension)
    And the units should auto-scale (mm or cm based on size)

  Scenario: Geometry information display
    When the info panel is visible
    Then I should see the model volume
    And the volume should display in mm³, cm³, or Liters depending on magnitude
    And I should see the surface area in mm² or cm²

  Scenario: Material and weight display
    When the info panel is visible
    Then I should see the currently selected material
    And I should see the calculated weight
    And I should see a hint about the M key shortcut

  Scenario: Model position display
    When the info panel is visible
    Then I should see the center coordinates (X, Y, Z)
    And the values should be displayed to 1 decimal place

  Scenario: Slicing status in info panel
    Given slicing is active and some triangles are clipped
    When I view the info panel
    Then the triangle count should show "visible / total" format
    And the text should be orange to indicate clipping is active

  Scenario: Collapsible sections
    When I click on a section header in the info panel
    Then the section should collapse or expand
    And a chevron indicator should show the section state
    And the collapse/expand should animate smoothly

  Scenario: Default section state
    When the info panel first appears
    Then all sections should be expanded by default
