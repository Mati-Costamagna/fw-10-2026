#include <iostream>
#include <stdexcept>

class Date {
public:
    Date(int mn, int dy, int yr) : month(mn), day(dy), year(yr) {
        if (mn < 1 || mn > 12) {
            throw std::invalid_argument("month must be in [1, 12]");
        }
    }

    int getMonth() const {
        // month = month + 1; // ERROR: no se puede modificar el dato dentro de un metodo const
        return month;
    }

    int getDay() const {
        return day;
    }

    int getYear() const {
        return year;
    }

    void setMonth(int mn) {
        if (mn < 1 || mn > 12) {
            throw std::invalid_argument("month must be in [1, 12]");
        }
        month = mn;
    }

private:
    int month;
    int day;
    int year;
};

void printDate(const Date& d) {
    // d es una referencia const: se puede leer, no modificar.
    std::cout << d.getDay() << '/' << d.getMonth() << '/' << d.getYear() << '\n';
    // d.setMonth(12); // ERROR: no se puede modificar a traves de const Date&
}

Date& setToJanuary(Date& d) {
    d.setMonth(1);
    return d; // Retorno por referencia mutable
}

const Date& dateWithSmallerMonth(const Date& a, const Date& b) {
    // Retorno por referencia const: evita copia y no permite modificar el resultado.
    if (a.getMonth() <= b.getMonth()) {
        return a;
    }
    return b;
}

int main() {
    Date myDate(7, 4, 1998);
    const Date birthDate(1, 18, 1953);

    myDate.setMonth(4); // OK: objeto no-const
    std::cout << "myDate month: " << myDate.getMonth() << '\n';

    std::cout << "birthDate month: " << birthDate.getMonth() << '\n'; // OK: metodo const

    // birthDate.setMonth(4); // ERROR: no se puede llamar metodo no-const sobre objeto const

    std::cout << "printDate(myDate): ";
    printDate(myDate); // OK: Date -> const Date&

    std::cout << "printDate(birthDate): ";
    printDate(birthDate); // OK: const Date -> const Date&

    setToJanuary(myDate); // OK: parametro Date& (mutable)
    std::cout << "myDate month after setToJanuary: " << myDate.getMonth() << '\n';

    // setToJanuary(birthDate); // ERROR: no se puede pasar const Date a Date&

    const Date anotherDate(12, 25, 2020);
    const Date& firstInYear = dateWithSmallerMonth(birthDate, anotherDate);
    std::cout << "smaller month is: " << firstInYear.getMonth() << '\n';

    // firstInYear.setMonth(8); // ERROR: firstInYear es const Date&

    return 0;
}


// g++ -Wall -Wextra -pedantic constant_member_function.cpp -o constant_member_function && ./constant_member_function
