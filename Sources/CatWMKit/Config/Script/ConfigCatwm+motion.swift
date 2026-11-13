import Foundation

extension ConfigCatwm {
    static let motion = #"""
      function style(name) {
        guardWrite();
        if (name === undefined) {
          return ["enabled", "duration", "curve", "bounce"].forEach((key) => assign(`motion.${key}`, undefined));
        }
        const found = setup.styles.find((item) => item.id === String(name).toLowerCase());
        if (!found) throw usage(`unknown motion style \`${name}\` (${setup.styles.map((item) => item.id).join(", ")})`);
        for (const key of Object.keys(found.fields)) assign(`motion.${key}`, found.fields[key]);
      }

      function currentStyle() {
        const match = setup.styles.find((item) =>
          Object.keys(item.fields).every((key) => readPath(`motion.${key}`) === item.fields[key]));
        return match ? match.id : undefined;
      }
    """#
}
