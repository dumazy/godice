/// An integer 3D vector, used for the accelerometer readings sent by the die
/// and for the reference "face up" vectors of each shell.
final class Vector3 {
  /// Creates a vector from its three components.
  const Vector3(this.x, this.y, this.z);

  /// X component.
  final int x;

  /// Y component.
  final int y;

  /// Z component.
  final int z;

  /// Squared euclidean distance to [other]. Enough for nearest-neighbour
  /// comparisons and avoids a square root.
  int squaredDistanceTo(Vector3 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return dx * dx + dy * dy + dz * dz;
  }

  @override
  bool operator ==(Object other) =>
      other is Vector3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '($x, $y, $z)';
}
