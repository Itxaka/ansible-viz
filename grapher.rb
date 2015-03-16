#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require './graphviz'
require 'fileutils'
require 'ostruct'
require 'pp'


class Grapher
  def graph(dict, options)
    g = Graph.new
    g[:rankdir] = 'LR'
    g[:tooltip] = ' '

    add_nodes(g, dict)
    connect_playbooks(g, dict)
    connect_roles(g, dict)
    hide_dull_tasks(g, dict)

    decorate(g, dict, options)

    if not options.show_vars
      to_cut = g.nodes.find_all {|n| n.data[:type] == :var }
      g.cut(*to_cut)
    end

    g
  end

  def add_nodes(g, dict)
    dict[:role].each_pair {|name, role|
      add_node(g, role)
      role[:task].each_pair {|n, task| add_node(g, task, task[:role]) }
      role[:varset].each_pair {|vsn, vs|
        vs[:var].each_pair {|vn, v| add_node(g, v, vs) }
      }
    }
    dict[:playbook].each_pair {|name, playbook|
      add_node(g, playbook)
      playbook[:role].each {|role| add_node(g, role) }
      playbook[:task].each {|task| add_node(g, task, task[:role]) }
    }
  end

  def add_node(g, it, parent=nil)
    name = it[:name]
    if parent
      name = parent[:name] + "::" + name
    end
    node = g.get_or_make(name)
    node.data = it
    it[:node] = node
    node[:label] = it[:name]
  end

  def connect_playbooks(g, dict)
    dict[:playbook].each_value {|playbook|
      (playbook[:role] || []).each {|role|
        g.add GEdge[playbook[:node], role[:node],
          {:tooltip => "includes"}]
      }
      (playbook[:task] || []).each {|task|
        g.add GEdge[playbook[:node], task[:node],
          {:style => 'dashed', :color => 'blue',
           :tooltip => "calls task"}]
      }
    }
  end

  def connect_roles(g, dict)
    dict[:role].each_value {|role|
      (role[:role_deps] || []).each {|dep|
        g.add GEdge[role[:node], dep[:node],
          {:color => 'hotpink',
           :tooltip => "calls foreign task"}]
      }

      (role[:task] || []).each_value {|task|
        g.add GEdge[role[:node], task[:node],
          {:tooltip => "calls task"}]

#        (task[:used_vars] || []).each {|var|
#          g.add GEdge[task[:node], var[:node],
#            {:style => 'dotted',
#             :tooltip => "uses var"}]
#        }
      }

      (role[:varset] || []).each_value {|vs|
        vs[:var].each_value {|v|
          g.add GEdge[role[:node], v[:node],
            {:tooltip => "provides var"}]
        }
      }
    }
  end

  def hide_dull_tasks(g, dict)
    dict[:role].values.each {|r|
      hide_tasks = r[:task].each_value.find_all {|it|
        it[:name] =~ /^_|^main$/
      }.map {|it| it[:node] }
      g.lowercut(*hide_tasks)
    }
  end


  ########## DECORATE ###########

  def decorate(g, dict, options)
    decorate_nodes(g, dict, options)

    dict[:role].values.map {|r| r[:node] }.each {|node|
      if node.inc_nodes.empty?
        node[:fillcolor] = 'yellowgreen'
        node[:tooltip] = 'not used by any playbook'
      end
    }

    # FIXME
#    dict[:role].values.each {|r|
#      r[:var].each_value {|v|
#        if not v[:used]
#          v[:node][:fillcolor] = 'yellow'
#          v[:node][:tooltip] += '. (EXPERIMENTAL) appears not to be used by any task in the owning role'
#        elsif not v[:defined]
#          v[:node][:fillcolor] = 'red'
#          v[:node][:tooltip] += '. (EXPERIMENTAL) not defined by this role;' +
#                            ' could be included from another role or not really a var'
#        end
#      }
#    }
  end

  def decorate_nodes(g, dict, options)
    types = {:playbook => {:shape => 'folder', :fillcolor => 'cornflowerblue'},
             :role => {:shape => 'house', :fillcolor => 'palegreen'},
             :task => {:shape => 'octagon', :fillcolor => 'cornsilk'},
             :var => {:shape => 'oval', :fillcolor => 'white'}}
    g.nodes.each {|node|
      type = node.data[:type]
      types[type].each_pair {|k,v| node[k] = v }
      node[:style] = 'filled'
      node[:tooltip] = type.to_s.capitalize
      case type
      when :task  # FIXME , :var
        node[:tooltip] += " #{node.data[:role][:name]}::#{node.data[:name]}"
      else
        node[:tooltip] += " " + node.data[:name]
      end
    }
  end
end

# This is accessed as a global from graph_viz.rb, EWW
def rank_node(node)
  case node.data[:type]
  when :playbook then :source
  when :task then :same
  when :var then :sink
  end
end
