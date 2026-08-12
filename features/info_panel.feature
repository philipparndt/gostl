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

  Scenario: A collapsed section keeps a row of icons
    Given the panel is showing
    When I collapse a section
    Then the section keeps one icon for each action it offers
    And each icon names its action and its key on hover
    And modes and toggles that are on are drawn in orange
    And "Open with go3mf" is one of the icons under Tools

    Examples:
      | section | icons                                                              |
      | Info    | material                                                           |
      | View    | wireframe, grid, slicing, build plate, home view, reset view       |
      | Tools   | distance, angle, radius, triangles, level, open with go3mf         |

  Scenario: A collapsed section is never wider than the panel
    Given the panel is narrower than the row of icons it holds
    When I collapse a section
    Then the icons wrap onto as many lines as they need
    And none of them is clipped or hidden behind a scroller

  Scenario: A collapsed section follows the state, as the open one does
    Given a measurement is being collected
    When I collapse the Tools section
    Then it keeps the actions that exist in that state, ending and cancelling it
    And the measurement tools come back when the measurement is over

  Scenario: Default section state
    When the info panel first appears
    Then all sections should be expanded by default
