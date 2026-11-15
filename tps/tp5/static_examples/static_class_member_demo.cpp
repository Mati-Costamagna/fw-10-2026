#include <iostream>

class Sensor {
public:
    explicit Sensor(int id) : id_(id) {
        ++instances_created; // Compartido entre todas las instancias.
    }

    int id() const {
        return id_;
    }

    static int createdCount() {
        return instances_created;
    }

private:
    int id_;
    static int instances_created; // Declaracion del miembro estatico.
};

int Sensor::instances_created = 0; // Definicion (una sola vez fuera de la clase).

int main() {
    Sensor s1(101);
    Sensor s2(102);

    std::cout << "s1 id: " << s1.id() << '\n';
    std::cout << "s2 id: " << s2.id() << '\n';

    std::cout << "instancias creadas: " << Sensor::createdCount() << '\n';
    std::cout << "instancias creadas (via objeto): " << s1.createdCount() << '\n';

    return 0;
}
