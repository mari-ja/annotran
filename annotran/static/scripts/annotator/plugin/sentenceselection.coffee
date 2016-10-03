Annotator = require('annotator')
$ = Annotator.$
xpathRange = Annotator.Range
Util = Annotator.Util

# This plugin implements the UI code for selecting sentences by clicking
module.exports = class SentenceSelection extends Annotator.Plugin

  pluginInit: ->
    # Register the event handlers required for creating a selection
    $(document).bind({
      "click": @findASentence
    })

    this.operational = false
    this.currentIndex = 0
    this.currentSentence = 0
    this.storedEvent = null
    this.extentElement = null

    null

  destroy: ->
    $(document).unbind({
      "click": @findASentence
    })
    super

  toggleOperation: () ->
    this.operational = not this.operational

  anchorToPage: (data) ->
    anchor = new xpathRange.SerializedRange(data).normalize(document)

    window.getSelection().removeAllRanges()
    window.getSelection().addRange(anchor.toRange())

    return null

  normalizeStyleTags: (target) ->

    return target

    # Get the currently selected ranges.
    tagName = $(target).prop("tagName").toLowerCase()

    # this loop checks that we are not within a formatting cell and that we should recurse upwards through parent elements
    while tagName is "i" or tagName is "strong" or tagName is "em" or tagName is "b" or tagName is "mark" or tagName is "small" or tagName is "del" or tagName is "ins" or tagName is "sub" or tagName is "sup"
      target = $(target).parent()
      tagName = $(target).prop("tagName").toLowerCase()

    return target

  packageData: (initialTarget, endTarget, endIndex) ->
    full_xpath = Util.xpathFromNode($(initialTarget), document)
    end_xpath = Util.xpathFromNode($(endTarget), document)

    data = {
      start: full_xpath
      startOffset: this.currentIndex
      end: end_xpath
      endOffset: endIndex + 1
    }

    return data

  selectSentence: (initialTarget, currentTarget = undefined, force = false) ->

    if currentTarget == undefined
        currentTarget = initialTarget

    desiredText = $(currentTarget).text()
    match = /[.!?]/.test(desiredText)
    desiredText = desiredText.split(/[.!?]/)

    offset_to_use = 0
    counter = 0

    if desiredText.length == 1
      desiredText = []
      desiredText.push $(currentTarget).text()

    for sentence in desiredText
      if counter == this.currentSentence
        break
      offset_to_use = offset_to_use + sentence.length
      counter = counter + 1

    if desiredText.length == 1
      desiredText = $(currentTarget).text()
    else
      desiredText = desiredText[this.currentSentence]

    endIndex = offset_to_use + desiredText.length + this.currentSentence + 1

    if endIndex > $(currentTarget).text().length - 1
      endIndex = $(currentTarget).text().length - 1

    # test if we have found a sentence marker or if we are forcing this through anyway
    if match or force
      data = this.packageData(initialTarget, currentTarget, endIndex)
      this.anchorToPage(data)
    else
      # here want to test:
      # 1. is there a sibling element?
      # 2. is there a parent element with a next sibling?
      nextSibling = $(currentTarget).next()

      if nextSibling != undefined and nextSibling.length != 0
        this.selectSentence initialTarget, nextSibling
      else
        nextSibling = this.findNextJumpNode(currentTarget)

        if nextSibling != undefined and nextSibling.length != 0
          this.selectSentence initialTarget, currentTarget, true
        else
          this.selectSentence initialTarget, nextSibling

  findASentence: (event = {}) =>
    this.storedEvent = event

    this.currentIndex = 0
    this.currentSentence = 0
    this.selectSentence event.target

    selection = Annotator.Util.getGlobal().getSelection()
    ranges = for i in [0...selection.rangeCount]
      r = selection.getRangeAt(0)
      if r.collapsed then continue else r

    if ranges.length
      event.ranges = ranges
      @annotator.onSuccessfulSelection event
      @annotator.createAnnotation()

    return null

  # This is called when the mouse is clicked on a DOM element.
  # Checks to see if there is a sentence that we can select, if so
  # calls Annotator's onSuccessfulSelection method.
  #
  # event - The event triggered this. Usually it's a click Event
  #
  # Returns nothing.
  makeSentenceSelection: (event = {}) =>
    if this.operational == false
      # we are not in sentence selection mode
      return

    this.storedEvent = event

    this.currentIndex = 0
    this.currentSentence = 0
    this.selectSentence event.target

    selection = Annotator.Util.getGlobal().getSelection()
    ranges = for i in [0...selection.rangeCount]
      r = selection.getRangeAt(0)
      if r.collapsed then continue else r

    if ranges.length
      event.ranges = ranges
      @annotator.onSuccessfulSelection event
      @annotator.createAnnotation()

    return null

  findNextJumpNode: (target) ->
    parent = $(target).parent()

    nextSibling = $(parent).next()

    if nextSibling == undefined
      return this.findNextJumpNode parent

    else if nextSibling.length == 0

      tagName = $(nextSibling).prop("tagName")

      if tagName != undefined
        tagName = tagName.toLowerCase()

        if tagName == 'body' or tagName == 'html'
          return nextSibling
        else
          return this.findNextJumpNode parent
      else
        return this.findNextJumpNode parent

    return nextSibling

  moveToNextSentence: (event) ->
    if this.operational == false
      # we are not in sentence selection mode
      return

    currentSelection = window.getSelection()

    this.currentIndex = currentSelection.extentOffset
    this.currentSentence = this.currentSentence + 1

    elementToUse = currentSelection.extentNode.parentElement

    if elementToUse.textContent.length <= (this.currentIndex)
      nextSibling = $(elementToUse).next()

      this.currentIndex = 0
      this.currentSentence = 0

      # algorithm here is:
      # 1. check if there is a sibling
      # 2. if there is no sibling, check the parent
      # 3. if the parent has a sibling, use that
      # 4. if the parent has no sibling, pass parent as element to 2

      if nextSibling == undefined or nextSibling.length == 0
        nextSibling = this.findNextJumpNode(elementToUse)

      elementToUse = nextSibling

    this.selectSentence elementToUse

    selection = Annotator.Util.getGlobal().getSelection()
    ranges = for i in [0...selection.rangeCount]
      r = selection.getRangeAt(0)
      if r.collapsed then continue else r

    if event == undefined
      # load the initial click event and use this as the default "base" event
      # this is needed so that the range is accurately described
      event = this.storedEvent

    if ranges.length
      event.ranges = ranges
      @annotator.onSuccessfulSelection event
      @annotator.createAnnotation()

    return null
