describe("Wagn", function() {
  describe("line_to_paragraph", function() {
    it("should change the element's class", function() {
      var el = j('<div class="line">foo</div>');
      Wagn.line_to_paragraph(el[0]);
      expect(el.hasClass("paragraph")).toBeTruthy();
      expect(el.hasClass("line")).toBeFalsy();
    });
  });
});