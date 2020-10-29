# Contributors: Hiro_r_b#7841
# (Discord)     mikemar10#9709

class HexagonRotate
  attr_gtk

  class Primitive
    attr_accessor :x, :y, :r, :g, :b, :a

    def initialize(x: 0, y: 0, r: 255, g: 255, b: 255, a: 255, **kw)
      @x = x; @y = y; @r = r; @g = g; @b = b; @a = a
      kw.each do |name, val|
        singleton_class.class_eval { attr_accessor "#{name}" }
        send("#{name}=", val)
      end
    end
  end

  class Solid < Primitive
    def initialize(w: 0, h: 0, **kw)
      super(primitive_marker: :solid, w: w, h: h, **kw)
    end

    def draw_override(ffi_draw)
      ffi_draw.draw_solid(@x, @y, @w, @h, @r, @g, @b, @a)
    end
  end

  class Sprite < Primitive
    def initialize(path:, w: 0, h: 0, **kw)
      super(primitive_marker: :sprite, w: w, h: h, path: path, **kw)
    end

    def draw_override(ffi_draw)
      ffi_draw.draw_sprite_3(@x, @y, @w, @h,
                             @path,
                             @angle,
                             @a, @r, @g, @b,
                             nil, nil,
                             nil, nil, nil, nil,
                             @angle_anchor_x, @angle_anchor_y,
                             nil, nil, nil, nil)
    end
  end

  # Altered variant of mikemar10's procedural hexagons
  class Hexagon
    attr_reader :radius
    attr_accessor :x, :y, :r, :g, :b, :a, :angle,
                  :ord_x, :ord_y, :off_x, :off_y, :center

    def self.sqrt3
      @sqrt3 ||= Math.sqrt(3)
    end

    def self.rt_name
      @rt_name ||= [*('a'..'z')].shuffle[0, 6].join
    end

    def self.rt
      @rt ||= $gtk.args.render_target(rt_name()).tap do |target|
        target.width = 1
        target.height = 1
        target.solids << Solid.new(w: 1, h: 1)
      end
    end

    def initialize(x:, y:, radius:, r:, g:, b:, a:, angle:,
                   ord_x:, ord_y:, off_x:, off_y:, center:)
      @x       = x
      @y       = y
      @radius  = radius
      @height  = radius * Hexagon.sqrt3
      @r       = r
      @g       = g
      @b       = b
      @a       = a
      @angle   = angle
      @ord_x   = ord_x
      @ord_y   = ord_y
      @off_x   = off_x
      @off_y   = off_y
      @center  = center
      @sprites = 3.map_with_index do |n|
        Sprite.new(x: x + @radius / 2,
                   y: y,
                   w: @radius,
                   h: @height,
                   path: Hexagon.rt_name(),
                   angle: 30 + 60 * n + @angle,
                   r: @r,
                   g: @g,
                   b: @b,
                   a: @a,
                   angle_anchor_x: 0.5,
                   angle_anchor_y: 0.5)
      end

      Hexagon.rt()
    end

    def radius= radius
      @height = radius * Hexagon.sqrt3
      @radius = radius
    end

    def w
      @radius * 2
    end

    def h
      @height
    end

    def draw_override(ffi_draw)
      i = 0
      while i < 3
        s       = @sprites[i]
        s.x     = @x + @radius / 2
        s.y     = @y
        s.w     = @radius
        s.h     = @height
        s.angle = 30 + 60 * i + @angle
        s.r     = @r
        s.g     = @g
        s.b     = @b
        s.a     = @a
        s.draw_override(ffi_draw)

        i += 1
      end
    end
  end

  def mouse
    inputs.mouse
  end

  def defaults
    state.tile_size       = 160
    state.tile_w          = Math.sqrt(3) * state.tile_size.half
    state.tile_h          = state.tile_size * 3/4
    state.tiles_x_count   = 1280.idiv(state.tile_w) - 1
    state.tiles_y_count   = 720.idiv(state.tile_h) - 1
    state.world_width_px  = state.tiles_x_count * state.tile_w
    state.world_height_px = state.tiles_y_count * state.tile_h
    state.world_x_offset  = (1280 - state.world_width_px).half
    state.world_y_offset  = (720 - state.world_height_px).half
    state.tiles           = state.tiles_x_count.map_with_ys(state.tiles_y_count) do |ord_x, ord_y|
      off_x   = (ord_y.even?) ?
                (state.world_x_offset + state.tile_w.half.half) :
                (state.world_x_offset - state.tile_w.half.half)
      off_y   = state.world_y_offset
      w       = state.tile_w
      h       = state.tile_h
      x       = off_x + ord_x * w
      y       = off_y + ord_y * h
      center  = { x: x + w.half,
                 y: y + h.half }
      radius  = [w.half, h.half].max
      r, g, b = [255, 127, 127].shuffle

      Hexagon.new(x: x,
                  y: y,
                  radius: radius,
                  r: r,
                  g: g,
                  b: b,
                  a: 127,
                  angle: 0,
                  ord_x: ord_x,
                  ord_y: ord_y,
                  off_x: off_x,
                  off_y: off_y,
                  center: center)
    end

    state.selected_tile = nil
    state.rotate_mode   = false
    state.rotation      = 0
    state.rot_ini       = nil
    state.rot_grab_ini  = nil
    state.rot_grab_cur  = 0
    state.snap_angles   = (0..7).map { |i| i * Math::PI/3 }
    state.force         = 0.1
    state.float_max     = 10
    state.float         = 0
    state.float_speed   = 5
  end

  def nearest_angle(angle, angles)
    angles.min_by { |x| (angle-x).abs }
  end

  def snapped? angle, angles
    angle == nearest_angle(angle, angles)
  end

  def input
    if mouse.click && !state.rotate_mode
      tile = state.tiles.find { |t| mouse.click.point_inside_circle? t.center, t.radius }
      if tile && tile.a == 127
        points = (0..7).map do |i|
          r = i * Math::PI/3
          { x: tile.center.x + tile.w * Math.cos(r),
            y: tile.center.y + tile.w * Math.sin(r) }
        end

        tiles = state.tiles.select do |t|
          points.any? do |p|
            p.point_inside_circle? t.center, t.radius
          end
        end
        tiles.each { |t| t.a = t.a == 255 ? 127 : 255 }

        state.rotate_mode = true
        state.selected_tile = tile
      end
    elsif state.rotate_mode
      if mouse.button_left && # Mouse is hovered around selected hexagons
         mouse.point.point_inside_circle?(state.selected_tile.center, state.selected_tile.radius * 3) &&
         !mouse.point.point_inside_circle?(state.selected_tile.center, state.selected_tile.radius)

        point = { x: state.selected_tile.center.x,
                  y: state.selected_tile.center.y }

        state.rot_ini      ||= state.rotation
        state.rot_grab_ini ||= point.angle_to(mouse.point).to_radians
        state.rot_grab_cur   = point.angle_to(mouse.point).to_radians
        state.rotation       = state.rot_grab_cur - state.rot_grab_ini + state.rot_ini # Rotate hexes from any point of grabbing
        state.force          = 0
      else
        state.rot_grab_ini = nil
        state.rot_ini      = nil
        state.force        = 0.02
      end

      if mouse.button_right && snapped?(state.rotation, state.snap_angles)
        tiles  = state.tiles.select { |t| t.a == 255 }
        colors = tiles.map { |t| [t.r, t.g, t.b] }
        tiles.map_with_index  do |t, i|
          point = { x: t.x + t.w.half,
                    y: t.y + t.h.half }
          tile  = state.tiles.find { |tile| point.point_inside_circle?(tile.center, tile.radius * 0.8) }
          tile.r, tile.g, tile.b = colors[i]
        end
        tiles.each { |t| t.a = 127; t.angle = 0 }

        state.rotate_mode = false
        state.rotation = 0
      end
    end
  end

  def update
    state.float     = if state.rotate_mode # Float hex selection upwards really fast
                        state.float.towards(state.float_max, state.float_speed)
                      else # Or drop instantly
                        0
                      end
    state.rotation  = state.rotation.towards(nearest_angle(state.rotation, state.snap_angles), state.force)
    state.rotation %= 2 * Math::PI
  end

  def render
    outputs.background_color = [0, 0, 0]

    bg_tiles = state.tiles.select { |t| t.a == 127 }
    bg_tiles.each do |t| # Set all hexes to default locations
      point = { x: t.off_x + t.ord_x * t.w,
                y: t.off_y + t.ord_y * t.h }
      t.x   = point.x
      t.y   = point.y
    end

    fg_tiles = state.tiles.select { |t| t.a == 255 }
    fg_tiles.map do |t| # Set hexes at rotated positions
      tile      = state.selected_tile
      point     = { x: t.off_x + t.ord_x * t.w,
                    y: t.off_y + t.ord_y * t.h }
      vx        = point.x - tile.x
      vy        = point.y - tile.y
      vm        = Math.sqrt(vx*vx + vy*vy)
      old_angle = Math.atan2(vy, vx)

      r = state.rotation
      va = Math.sin(3 * r).abs # Intersects 0 at every snap angle
      na = nearest_angle(r, state.snap_angles)
      ans = na >= r ? r + (na - r) * va : r + (r - na) * va # Provides the visual SNAP!
      new_angle = old_angle + ans
      new_point = [tile.x + vm * Math.cos(new_angle),
                   tile.y + vm * Math.sin(new_angle)]
      t.x       = new_point.x
      t.y       = new_point.y + state.float
      t.angle   = new_angle.to_degrees
    end

    outputs.sprites << bg_tiles
    outputs.sprites << fg_tiles

    # DEBUG ## vvvvvvvvvvvvvvvvvvvvvv
    # tiles = state.tiles.select { |t| t.a == 255 }
    # tiles.each do |t|
    #   point = { x: t.x + t.w.half,
    #             y: t.y + t.h.half }

    #   tile = state.tiles.find { |tile| point.point_inside_circle?(tile.center, tile.radius * 0.8) }

    #   outputs.primitives << [point.x, point.y, 10, 10].solid
    #   outputs.primitives << [tile.center.x, tile.center.y, 10, 10, 255, 0, 0].solid if tile
    # end

    # tile = state.tiles.find { |t| inputs.mouse.position.point_inside_circle? t.center, t.radius }
    # outputs.primitives << [tile.x, tile.y, 10, 10, 255, 255, 255].solid if tile
    # outputs.primitives << [tile.center.x, tile.center.y, 10, 10, 255, 255, 255].solid if tile

    # outputs.labels << [0, 720, "FPS: #{gtk.current_framerate}", 0, 0, 255, 255, 255]
    # outputs.labels << [0, 700, "Angle: #{nearest_angle(state.rotation, state.snap_angles)}", 0, 0, 255, 255, 255]
    # outputs.labels << [0, 680, "Rot: #{state.rotation}", 0, 0, 255, 255, 255]
    # DEBUG ## ^^^^^^^^^^^^^^^^^^^^^^^
  end

  def tick
    defaults if args.tick_count.zero?
    input
    update
    render
  end
end

$game = HexagonRotate.new
def tick args
  $game.args = args
  $game.tick
end
$gtk.reset
