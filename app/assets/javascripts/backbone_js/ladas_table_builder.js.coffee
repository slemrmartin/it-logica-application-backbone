class TableBuilder
  @render_tbody: (obj) ->
    TableBuilder.obj = obj

    TableBuilder.html = ""

    TableBuilder.make_table()

    return TableBuilder.html

  @make_table: ->
    for row in TableBuilder.obj.data
      do (row) ->
        TableBuilder.html += '<tr>'

        # todo make possible to insertt function on the first or last column
        TableBuilder.add_row_checkboxes(row)
        TableBuilder.add_row_functions(row)
        TableBuilder.add_row_columns(row)

        TableBuilder.html += '</tr>'

    TableBuilder.add_summary_row()

  @add_summary_row: ->
    functions_present = TableBuilder.obj.row? && TableBuilder.obj.row.functions?

    # code for sumarizes of the page (paginated)
    TableBuilder.html += '<tr class="summarize_page">'
    # todo make sure functions collumn got skipped when placement is different, eg. on the end
    TableBuilder.html += '<td class="summarize"></td>' if functions_present
    TableBuilder.html += '<td class="summarize"></td>' if TableBuilder.obj.checkboxes?
    for col in TableBuilder.obj.columns
      do (col) ->
        TableBuilder.html += '<td class="summarize">'
        if col.summarize_page? || col.summarize_page_value?
          TableBuilder.html += '<div class="summarize_page">'
          TableBuilder.html += if col.summarize_page_label? then col.summarize_page_label else '<span class="label">Celkem na stránce: </span>'
          TableBuilder.html += if col.summarize_page_value? then col.summarize_page_value else 0
          TableBuilder.html += '</div>'

        TableBuilder.html += '</td>'
    TableBuilder.html += '</tr>'

    # code for sumarizes of the all filtered data (paginated is not used)
    TableBuilder.html += '<tr class="summarize_all">'
    TableBuilder.html += '<td class="summarize"></td>' if functions_present
    TableBuilder.html += '<td class="summarize"></td>' if TableBuilder.obj.checkboxes?
    for col in TableBuilder.obj.columns
      do (col) ->
        TableBuilder.html += '<td class="summarize">'
        if col.summarize_all? || col.summarize_all_value?
          TableBuilder.html += '<div class="summarize_all">'
          TableBuilder.html += if col.summarize_all_label? then col.summarize_all_label else '<span class="label">Celkem: </span>'
          TableBuilder.html += if col.summarize_all_value? then col.summarize_all_value else 0
          TableBuilder.html += '</div>'
        TableBuilder.html += '</td>'
    TableBuilder.html += '</tr>'

  @add_row_checkboxes: (row) ->
    if TableBuilder.obj.checkboxes?
      TableBuilder.html += '<td class="checkbox_collumn">'
      TableBuilder.html += '<input type="checkbox" class="row_checkboxes" name="checkboxes[' + row.row_id + ']"'
      TableBuilder.html += ' onclick="CheckboxPool.change($(this))"'
      #console.log CheckboxPool.get_pool_by_form_id(TableBuilder.obj.form_id, row.row_id)
      #console.log CheckboxPool.include_value(TableBuilder.obj.form_id, row.row_id)
      TableBuilder.html += ' checked="checked"' if CheckboxPool.include_value(TableBuilder.obj.form_id, row.row_id)
      TableBuilder.html += ' value="' + row.row_id + '">'


      TableBuilder.html += '</td>'


  @add_row_functions: (row) ->
    if TableBuilder.obj.row? && TableBuilder.obj.row.functions?
      TableBuilder.html += '<td>'


      for function_name, settings of TableBuilder.obj.row.functions
        TableBuilder.make_row_function_button(settings, row)

      TableBuilder.html += '</td>'

  @add_row_columns: (row) ->
    for col in TableBuilder.obj.columns
      do (col) ->
        TableBuilder.html += '<td class="' + col.class + '">'

        if (is_hash(row[col.table + '_' + col.name]))
          # hash span or href (styled as button)
          button_settings = row[col.table + '_' + col.name]
          button_settings = {} if !button_settings?
          TableBuilder.make_column_from_hash(button_settings, row, col)

        else if (is_array(row[col.table + '_' + col.name]))
          # array of hashes (probably buttons)
          one_cell_buttons = row[col.table + '_' + col.name]
          for one_cell_button in one_cell_buttons
            do (one_cell_button) ->
              one_cell_button = {} if !one_cell_buttons?
              TableBuilder.make_column_from_hash(one_cell_button, row, col)

        else if (is_string(row[col.table + '_' + col.name]))
          # its just string
          text = ""
          text = row[col.table + '_' + col.name] if row[col.table + '_' + col.name]?
          text = row[col.name] if row[col.name]? && text? && text.length <= 0

          sliced_text = text
          if (col.max_text_length)
            max = col.max_text_length - 3
            sliced_text = sliced_text.slice(0, col.max_text_length) + "..." if ( max > 0 && sliced_text.length > max)

          TableBuilder.html += '<span title="' + text + '">' + sliced_text + '</span>'

        else
          # its something else eg. number cant be sliced, or its probably aliens Kveigars
          text = ""
          text = row[col.table + '_' + col.name] if row[col.table + '_' + col.name]?
          text = row[col.name] if row[col.name]? && text? && text.length <= 0
          # console.log[text]

          TableBuilder.html += '<span title="' + text + '">' + text + '</span>'

        TableBuilder.html += '</td>'


  @make_href_button: (settings, row, col) ->
    sliced_text = settings['name']
    if col?
      if (col.max_text_length)
        max = col.max_text_length - 3
        sliced_text = sliced_text.slice(0, col.max_text_length) + "..." if ( max > 0 && sliced_text.length > max)

    it_is_link = false
    it_is_link = true if (settings.url || settings.symlink_controller || settings.symlink_action || settings.symlink_id || settings.symlink_outer_controller || settings.symlink_outer_id)


    if it_is_link
      stringified_settings = JSON.stringify(settings)

      stringified_settings = stringified_settings.replace(/"/g, '&quot;')
      # this is crutial unless the double quotes will fuck up html
      non_ajax_url = build_get_url(settings)
      TableBuilder.html += '<a href="' + non_ajax_url + '"'
    else
      TableBuilder.html += '<span'

    TableBuilder.html += ' class="' + settings.class + '"' if settings.class?
    TableBuilder.html += ' title="' + settings.name + '"'
    TableBuilder.html += ' data-tr_class="' + settings.tr_class + '"' if  settings.tr_class?
    TableBuilder.html += ' data-td_class="' + settings.td_class + '"' if  settings.td_class? && settings.td_class.length > 0

    if it_is_link
      if (settings.confirm)
        TableBuilder.html += ' onclick="if (confirm(\'' + settings.confirm + '\')){ load_page(' + stringified_settings + ',this); }; return false;"'
      else
        TableBuilder.html += ' onclick="load_page(' + stringified_settings + ',this); return false;"'

    else if settings.js_code?
      # a javascrip code can be passed, it will be put as onclick javascript of the button
      TableBuilder.html += ' onclick="' + settings.js_code
      TableBuilder.html += '"'

    TableBuilder.html += '>' + sliced_text

    if it_is_link
      TableBuilder.html += '</a>'
    else
      TableBuilder.html += '</span>'




  @make_row_function_button: (button_settings, row, col) ->
    button_settings.symlink_id = row.row_id if row?
    # only for generic row functions, they are defined without the id
    TableBuilder.make_href_button(button_settings, row, col)

  @make_column_from_hash: (button_settings, row, col) ->
    button_settings['origin'] = 'table'
    TableBuilder.make_href_button(button_settings, row, col)


window.TableBuilder = TableBuilder





