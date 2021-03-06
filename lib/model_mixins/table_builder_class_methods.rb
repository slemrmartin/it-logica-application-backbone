module ModelMixins
  module TableBuilderClassMethods
    def prepare_settings(logged_user, object, settings, params, per_page = 10)
      params[:page] = 1 if params[:page].blank?
      params[:order_by] = settings[:default][:order_by] + " " + settings[:default][:order_by_direction] if params[:order_by].blank? && !settings[:default][:order_by].blank? && !settings[:default][:order_by_direction].blank?

      params[:order_by] = settings[:default][:order] if params[:order_by].blank? && !settings[:default][:order].blank?

      # there are allowed per_pages in the settings[:per_page]
      unless settings[:per_page].blank?
        unless params["per_page_chosen"].blank?
          params[:per_page] = settings[:per_page].include?(params["per_page_chosen"].to_i) ? params["per_page_chosen"].to_i : settings[:per_page].first
        end
      end


      params[:per_page] = settings[:default][:per_page] if params[:per_page].blank? && !settings[:default][:per_page].blank?
      params[:per_page] = per_page if params[:per_page].blank?
      per_page = params[:per_page]


      # method below can change this if there were some virtual non exixtent columns
      params[:real_order_by] = params[:order_by]
      check_non_existing_colum_order_by(settings, params)

      not_selected_items = object.filter(object, settings, params, per_page)
      items = not_selected_items.selection(settings)
      if params[:page].to_i > items.total_pages && items.total_pages > 0
        params[:page] = 1
        not_selected_items = object.filter(object, settings, params, per_page)
        items = not_selected_items.selection(settings)
      end

      # the array of items, Will be filled with column method values, formatting values, etc.
      all_items = items.all # maybe can be done more optimal

      if settings[:template].blank?
        # initialize another_global_formats,another_formats and column_methods
        another_global_formats = []
        another_formats = []
        column_methods = []
        settings[:columns].each do |col|
          if !col[:summarize_page].blank? && col[:summarize_page]
            # mysql SUM of the collumn on the page
            # passing all_items.total_entries because I don't want it to count again
            col[:summarize_page_value] = sumarize(object, col, object.filter(object, settings, params, per_page, all_items.total_entries).selection(settings))
          end

          if !col[:summarize_all].blank? && col[:summarize_all]
            # mysql SUM of the collumn off all data
            col[:summarize_all_value] = sumarize(object, col, object.filter(object, settings, params, false).selection(settings))
          end


          unless col[:global_format_method].blank?
            # ToDo dodelat moznost predani parametru do formatovaci metody
            col[:name] = col[:name].blank? ? "non_existing_column___" + col[:global_format_method] : col[:name]
            another_global_format = {:global_format_method => col[:global_format_method],
                                     :name => col[:name],
                                     :table => col[:table]}
            another_global_formats << another_global_format
          end
          unless col[:format_method].blank?
            col[:name] = col[:name].blank? ? "non_existing_column___" + col[:format_method] : col[:name]
            another_format = {:format_method => col[:format_method],
                              :name => col[:name],
                              :table => col[:table]}
            another_formats << another_format
          end
          unless col[:column_method].blank?
            column_methods << {:column_method => col[:column_method],
                               :name => col[:name],
                               :table => col[:table],
                               :column_class => col[:column_class],
                               :column_params => col[:column_params]
            }
          end
        end


        # same as template_items below, loads objects so column method are better to use
        # todo think about, but I dont need object, because it's making the same query twice, I just need class and with one outer join it return filtered data, and i include includes to it
        #template_items = object.joins("RIGHT OUTER JOIN (" + not_selected_items.select(settings[:row][:id] + " AS row_id").to_sql + ") temp_template_query ON #{settings[:row][:id]} = temp_template_query.row_id")
        # the AREL with items
        if object.respond_to?(:klass)
          template_items = object.klass.joins("RIGHT OUTER JOIN (" + items.uniq.to_sql + ") temp_template_query ON #{settings[:row][:id]} = temp_template_query.row_id")
        else
          template_items = object.joins("RIGHT OUTER JOIN (" + items.uniq.to_sql + ") temp_template_query ON #{settings[:row][:id]} = temp_template_query.row_id")
        end

        template_items = template_items.includes(settings[:includes])

        #template_items.all
        # todo dat do knowledge base, kdyz chci aby fungoval include nesmim volat all
        #template_items.each {|t| t.meeting_registrations.each {|x| puts x.inspect}}

        # calling column methods
        another_columns = {}
        unless column_methods.blank?
          column_method_settings = {:params => params}
          column_methods.each do |column_method|
            column_method_settings[:column_params] = column_method[:column_params]
            #all items == array of array items
            #template items == AREL
            if column_method[:column_class].blank?
              if object.respond_to?(:klass)
                another_columns[column_method[:column_method]] = object.klass.send(column_method[:column_method], logged_user, all_items, template_items, column_method_settings)
              else
                another_columns[column_method[:column_method]] = object.send(column_method[:column_method], logged_user, all_items, template_items, column_method_settings)
              end
            else
              column_method[:column_class] = column_method[:column_class].constantize if column_method[:column_class].kind_of?(String)
              another_columns[column_method[:column_method]] = column_method[:column_class].send(column_method[:column_method], logged_user, all_items, template_items, column_method_settings)
            end
          end
        end

        # updating items by another_global_formats,another_formats, column_methods, summary_methods
        if another_global_formats.blank? && another_formats.blank? && column_methods.blank? &&
            items_array = items
        else
          items_array = []
          all_items.each do |i|
            attrs = i.attributes
            another_global_formats.each do |another_global_format|
              # todo udelat moznost predani dalsich parametru
              case another_global_format[:table]
                when "___sql_expression___"
                  col_name = "#{another_global_format[:name]}"
                else
                  col_name = "#{another_global_format[:table]}_#{another_global_format[:name]}"
              end
              attrs.merge!({col_name => i.send(another_global_format[:global_format_method].to_sym, attrs[col_name])})
            end
            another_formats.each do |another_format|
              case another_format[:table]
                when "___sql_expression___"
                  col_name = "#{another_format[:name]}"
                else
                  col_name = "#{another_format[:table]}_#{another_format[:name]}"
              end

              attrs.merge!({col_name => i.send(another_format[:format_method].to_sym, attrs[col_name])})
            end
            column_methods.each do |column_method|
              another_column_row = "-"
              another_column_row = another_columns[column_method[:column_method]][attrs['row_id']] if !another_columns.blank? && !another_columns[column_method[:column_method]].blank? && !another_columns[column_method[:column_method]][attrs['row_id']].blank?
              attrs.merge!({"#{column_method[:table]}_#{column_method[:name]}" => another_column_row})
            end

            items_array << attrs
          end
        end

        settings.merge!({:data => items_array})
      else
        #template_items = object.joins("RIGHT OUTER JOIN (" + not_selected_items.uniq.select(settings[:row][:id] + " AS row_id").to_sql + ") temp_template_query ON #{settings[:row][:id]} = temp_template_query.row_id")
        if object.respond_to?(:klass)
          template_items = object.klass.joins("RIGHT OUTER JOIN (" + items.uniq.to_sql + ") temp_template_query ON #{settings[:row][:id]} = temp_template_query.row_id")
        else
          template_items = object.joins("RIGHT OUTER JOIN (" + items.uniq.to_sql + ") temp_template_query ON #{settings[:row][:id]} = temp_template_query.row_id")
        end

        template_items = template_items.includes(settings[:includes])
        settings.merge!({:data => template_items})
      end

      # summary_methods 
      unless settings[:summaries].blank?
        summaries = settings[:summaries]
        summaries.each do |summary|
          summary_settings = {:params => params}
          summary_settings[:summary_params] = summary[:summary_params]

          if summary[:summary_class].blank?
            if object.respond_to?(:klass)
              val = object.klass.send(summary[:summary_method], logged_user, all_items, template_items, object, summary_settings)
            else
              val = object.send(summary[:summary_method], logged_user, all_items, template_items, object, summary_settings)
            end
          else
            summary_class = summary[:summary_class].constantize if summary[:summary_class].kind_of?(String)
            val = summary_class.send(summary[:summary_method], logged_user, all_items, template_items, object, summary_settings)
          end
          if val.kind_of?(Hash)
            summary[:value] = val[:value]
            summary[:class] = val[:class]
          else
            summary[:value] = val
          end
        end

      end


      settings.merge!({:data_paginate => items})
      settings.merge!({:params => params})
      settings
    end

    def sumarize(object, col, items)
      #method for sumarizing values in column

      if col[:sql_expression].blank?
        col_name = "#{col[:table]}_#{col[:name]}"
      else
        col_name = col[:name]
      end

      if object.respond_to?(:klass)
        mysql_count = object.klass.find_by_sql("SELECT SUM(#{col_name}) AS sum_column FROM (" + items.to_sql + ") count")
      else
        mysql_count = object.find_by_sql("SELECT SUM(#{col_name}) AS sum_column FROM (" + items.to_sql + ") count")
      end

      #count = items.sum(col[:name])
      count = mysql_count.first[:sum_column]
    end

    def selection(settings)
      select_string = ""
      settings[:columns].each do |col|
        col[:table] = "___unknown___" if col[:table].blank?
        col[:table] = "___sql_expression___" unless col[:sql_expression].blank?

        if col[:column_method].blank? && col[:row_method].blank? && !col[:name].blank?
          if col[:sql_expression].blank?
            # I am selection col[:name]
            select_string += ", " unless select_string.blank?
            select_string += "#{col[:table]}.#{col[:name]} AS #{col[:table]}_#{col[:name]}"
          else
            # Iam selecting col[:expression] and col[:name] is alias
            # the expression can be sql expression
            select_string += ", " unless select_string.blank?
            select_string += "#{col[:sql_expression]} AS #{col[:name]}"
          end
        end

        # for select more data in combination with filter_method (etc full_name of user))
        if !col[:table].blank? && !col[:select].blank? && !col[:select_as].blank?
          col[:select_as] = col[:table] if col[:select_as].blank?

          col[:select].split(",").each do |one_select|
            one_select.gsub!(" ", "")
            select_string += ", " unless select_string.blank?
            select_string += "#{col[:select_as]}.#{one_select} AS #{col[:select_as]}_#{one_select}"
          end
        end

        # for (agregated data)
        #if (!col[:select_agregated].blank?
      end

      select_string += ", " unless select_string.blank?
      select_string += "#{settings[:row][:id]} AS row_id "


      select(select_string)
    end

    def filter(object, settings, params, per_page = 10, total_count = nil)
      order_by = params[:real_order_by]

      cond_str = ""
      cond_hash = {}
      having_cond_str = ""
      having_cond_hash = {}


      if !params.blank? && params['find']
        params['find'].each_pair do |i, v|
          i = i.gsub(/___unknown___\./, "") #some cleaning job
          unless v.blank?
            if i.match(/^.*?non_existing_column___.*$/i)
              identifier = i.split("non_existing_column___").second
              settings[:columns].each do |col|
                if !col[:select_as].blank? && !col[:format_method].blank? && col[:format_method] == identifier
                  cond_str += " AND " unless cond_str.blank?
                  cond_str += "( "
                  sub_cond = ""
                  col[:select].split(",").each do |sub_cond_col|
                    sub_cond += " OR " unless sub_cond.blank?
                    non_existing_column_i = col[:select_as] + "." + sub_cond_col.gsub(" ", "")
                    cond_id = "find_#{non_existing_column_i.gsub(/\./, '_')}"
                    sub_cond += "#{non_existing_column_i} LIKE :#{cond_id}" #OR guest_email LIKE :find"
                    cond_hash.merge!({cond_id.to_sym => "%#{v}%"})
                  end
                  cond_str += sub_cond + " )"
                else
                  ""
                end
              end
            else
              if i.match(/^.*?___sql_expression___.*$/i)
                i = i.gsub(/___sql_expression___\./, "") #some cleaning job

                having_cond_str += " AND " unless having_cond_str.blank?
                cond_id = "find_#{i.gsub(/\./, '_')}"
                having_cond_str += "#{i} LIKE :#{cond_id}" #OR guest_email LIKE :find"
                having_cond_hash.merge!({cond_id.to_sym => "%#{v}%"})
              else
                cond_str += " AND " unless cond_str.blank?
                cond_id = "find_#{i.gsub(/\./, '_')}"
                cond_str += "#{i} LIKE :#{cond_id}" #OR guest_email LIKE :find"
                cond_hash.merge!({cond_id.to_sym => "%#{v}%"})
              end
            end
          end
        end
      end


      # ToDo ladas add having condition to others
      if !params.blank? && params['multichoice']
        params['multichoice'].each_pair do |i, v|
          i = i.gsub(/___unknown___\./, "") #some cleaning job
          unless v.blank?
            cond_str += " AND " unless cond_str.blank?
            cond_id = "multichoice_#{i.gsub(/\./, '_')}"

            cond_str += "#{i} IN (:#{cond_id})" #OR guest_email LIKE :find"
            cond_hash.merge!({cond_id.to_sym => v})
          end
        end
      end

      if !params.blank? && (params['date_from'] || params['number_from'])
        from_hash = params['date_from']
        if from_hash.blank?
          from_hash = params['number_from']
        else
          from_hash.merge!(params['number_from']) unless params['number_from'].blank?
        end
        from_hash.each_pair do |i, v|
          i = i.gsub(/___unknown___\./, "") #some cleaning job
          unless v.blank?
            if i.match(/^.*?___sql_expression___.*$/i)
              i = i.gsub(/___sql_expression___\./, "") #some cleaning job
              having_cond_str += " AND " unless having_cond_str.blank?
              cond_id = "date_from_#{i.gsub(/\./, '_')}"
              having_cond_str += "#{i} >= :#{cond_id}" #OR guest_email LIKE :find"
              having_cond_hash.merge!({cond_id.to_sym => "#{v}"})
            else
              cond_str += " AND " unless cond_str.blank?
              cond_id = "date_from_#{i.gsub(/\./, '_')}"
              cond_str += "#{i} >= :#{cond_id}" #OR guest_email LIKE :find"
              cond_hash.merge!({cond_id.to_sym => "#{v}"})
            end
          end
        end
      end

      if !params.blank? && (params['date_to'] || params['number_to'])
        to_hash = params['date_to']
        if to_hash.blank?
          to_hash = params['number_to']
        else
          to_hash.merge!(params['number_to']) unless params['number_to'].blank?
        end
        to_hash.each_pair do |i, v|
          i = i.gsub(/___unknown___\./, "") #some cleaning job
          unless v.blank?
            if i.match(/^.*?___sql_expression___.*$/i)
              i = i.gsub(/___sql_expression___\./, "") #some cleaning job
              having_cond_str += " AND " unless having_cond_str.blank?
              cond_id = "date_to_#{i.gsub(/\./, '_')}"
              having_cond_str += "#{i} <= :#{cond_id}" #OR guest_email LIKE :find"
              having_cond_hash.merge!({cond_id.to_sym => "#{v}"})
            else
              cond_str += " AND " unless cond_str.blank?
              cond_id = "date_to_#{i.gsub(/\./, '_')}"
              cond_str += "#{i} <= :#{cond_id}" #OR guest_email LIKE :find"
              cond_hash.merge!({cond_id.to_sym => "#{v}"})
            end
          end
        end
      end

      ret = where(cond_str, cond_hash).order(order_by)
      ret = ret.having(having_cond_str, having_cond_hash) unless having_cond_str.blank?
      #items = self.joins("LEFT OUTER JOIN intranet_text_pages ON resource_id = intranet_text_pages.id").where(cond_str, cond_hash).paginate(:page => params[:page], :per_page => per_page).order(order_by).selection(settings)
      #if params[:page].to_i > items.total_pages && items.total_pages > 0
      #  params[:page] = 1
      #  items = self.where(cond_str, cond_hash).paginate(:page => params[:page], :per_page => per_page).order(order_by).selection(settings)
      #end
      #items

      # if there are additional joins i will add them
      settings[:columns].each do |col|
        col[:table_primary_key] = "id" if col[:table_primary_key].blank?
        if !col[:join_on].blank?
          join_on_select = col[:select] + ", #{col[:table_primary_key]}" # adding primary key so it can be used in on condition
          ret= ret.joins("LEFT OUTER JOIN (SELECT #{join_on_select} FROM #{col[:table]}) #{col[:select_as]} ON #{col[:select_as]}.#{col[:table_primary_key]}=#{col[:join_on]}")
        end
      end

      if per_page && per_page > 0
        # only when i need pagination
        if total_count.blank?
          # if I call this more times, I can pass the total count and not count it multiple times

          # fuck will paginate, if there are agregated queries that I use for condition, will_paginage will delete it
          # i am counting rows on my own (as sugested in will paginete gem, when the query got more complex)
          if object.respond_to?(:klass)
            mysql_count = object.klass.find_by_sql("SELECT COUNT(*) AS count_all FROM (" + ret.selection(settings).to_sql + ") count")
          else
            mysql_count = object.find_by_sql("SELECT COUNT(*) AS count_all FROM (" + ret.selection(settings).to_sql + ") count")
          end
          ret = ret.paginate(:page => params[:page], :per_page => per_page, :total_entries => mysql_count.first[:count_all])
        else
          ret = ret.paginate(:page => params[:page], :per_page => per_page, :total_entries => total_count)
        end
      end

      ret
    end


    def check_non_existing_colum_order_by(settings, params)
      order_by_params = params[:order_by].dup.gsub(/___unknown___\./, "") #some cleaning job
      order_by_params = order_by_params.gsub(/___sql_expression___\./, "") #some cleaning job

      order_by_arr = order_by_params.split(",")
      order_by_arr.each_with_index do |one_order_by, index|
        if one_order_by.match(/^.*?non_existing_column___.*$/i)
          identifier_and_direction = one_order_by.split("non_existing_column___").second
          identifier = identifier_and_direction.split(" ").first
          order_by_direction = identifier_and_direction.split(" ").second
          settings[:columns].each do |col|
            if !col[:select_as].blank? && !col[:format_method].blank? && col[:format_method] == identifier
              order_by_arr[index] = col[:order_by].gsub(",", " #{order_by_direction} ,") + " #{order_by_direction}"
            else
              ""
            end
          end
        else
          ""
        end
      end
      params[:real_order_by] = order_by_arr*","
    end
  end
end
