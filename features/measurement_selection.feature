@measurement @selection
Feature: Measurement Selection and Management
  As a user
  I want to select and manage measurements
  So that I can modify or delete specific measurements

  Background:
    Given the application is running
    And a 3D model is loaded
    And I have created multiple measurements

  Scenario: Rectangle selection with Option+drag
    When I hold Option and click and drag on the viewport
    Then a selection rectangle should appear
    And all measurements within the rectangle should be selected
    And selected measurements should be visually highlighted

  Scenario: Click to select measurement
    When I click on a measurement label
    Then the measurement should be selected
    And it should be visually highlighted

  Scenario: Click empty area to deselect
    Given one or more measurements are selected
    When I click on an empty area of the viewport
    Then all measurements should be deselected

  Scenario: Delete selected measurements
    Given one or more measurements are selected
    When I press Backspace or Delete
    Then the selected measurements should be removed
    And the remaining measurements should be preserved

  Scenario: Clear all measurements
    When I press Cmd+Shift+K
    Then all measurements should be removed
    And if a measurement is in progress, it should be cancelled

  Scenario: Clear measurements from menu
    When I select "Clear All Measurements" from the Tools menu
    Then all measurements should be removed

  Scenario: Measurement label positioning
    Given I have created a measurement
    Then the label should be positioned at the measurement point
    And the label should be rendered as 2D text over the 3D model
    And the label should use screen-space coordinates

  Scenario: Measurement color coding
    Given I have created different types of measurements
    Then each measurement type should have a distinct color
    And this helps distinguish between distance, angle, and radius measurements

  @selection @info-panel
  Scenario: View selected measurement coordinates
    Given I have created distance measurements
    And I select one or more measurements
    Then the info panel should display the selected measurements
    And each measurement should show its start point coordinates
    And each measurement should show its end point coordinates
    And the coordinates should be formatted as (x, y, z)

  @selection @info-panel
  Scenario: Selected measurement details for different types
    Given I have selected measurements of different types
    Then distance measurements show start and end coordinates
    And radius measurements show center coordinates
    And angle measurements show vertex coordinates

  @openscad @export
  Scenario: Copy measurements as OpenSCAD code
    Given I have created measurements
    When I press Cmd+Shift+C
    Then the measurements should be converted to OpenSCAD code
    And the code should be copied to the clipboard

  @openscad @export
  Scenario: Copy selected measurements as OpenSCAD code
    Given I have created multiple measurements
    And some measurements are selected
    When I press Cmd+Shift+C
    Then only the selected measurements should be converted to OpenSCAD code
    And the code should be copied to the clipboard

  @openscad @export
  Scenario: Copy measurements as OpenSCAD from menu
    When I select "Copy as OpenSCAD" from the Tools menu
    Then all measurements should be converted to OpenSCAD code
    And the code should be copied to the clipboard

  @openscad @export @polygon
  Scenario: Copy measurements as OpenSCAD polygon
    Given I have created distance measurements
    When I press Cmd+P
    Then the distance measurements should be converted to an OpenSCAD polygon
    And the polygon points should be extracted from measurement endpoints
    And the code should be copied to the clipboard

  @openscad @export @polygon
  Scenario: Copy selected measurements as polygon
    Given I have created multiple distance measurements
    And some measurements are selected
    When I press Cmd+P
    Then only the selected measurements should be converted to a polygon
    And the code should be copied to the clipboard

  @openscad @export @polygon
  Scenario: Copy measurements as polygon from panel
    Given I have selected distance measurements
    Then the info panel should show a "Copy as Polygon" button
    When I click the "Copy as Polygon" button
    Then the selected measurements should be converted to a polygon
    And the code should be copied to the clipboard

  @openscad @export
  Scenario: OpenSCAD polygon generation from closed shape
    Given I have created a closed polygon using distance measurements
    Then the generated OpenSCAD code should include a polygon definition
    And the polygon should be extruded with linear_extrude

  @openscad @export
  Scenario: OpenSCAD circle generation from radius measurement
    Given I have created a radius measurement
    Then the generated OpenSCAD code should include a circle definition
    And the circle should be positioned at the measured center
    And the circle should have the measured radius

  @openscad @export @triangles
  Scenario: Select triangles mode
    When I press T
    Then triangle selection mode should be activated
    And I can click on triangles to select them
    And clicking a selected triangle should deselect it

  @openscad @export @triangles
  Scenario: Copy selected triangles as OpenSCAD polyhedron
    Given I am in triangle selection mode
    And I have selected multiple triangles
    When I press Cmd+Shift+C
    Then an OpenSCAD polyhedron should be generated
    And the polyhedron should contain all selected triangle vertices
    And the polyhedron should contain all selected triangle faces
    And the code should be copied to the clipboard

  @openscad @export @triangles
  Scenario: Triangle selection generates proper polyhedron
    Given I have selected triangles forming a 3D shape
    When I copy as OpenSCAD
    Then the generated code should include a points array
    And the generated code should include a faces array
    And the generated code should call polyhedron()
