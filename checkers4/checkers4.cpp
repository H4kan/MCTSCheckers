

#include <iostream>
#include <SFML/Graphics.hpp>
#include <SFML/Window.hpp>

#define WINDOW_WIDTH 800
#define WINDOW_HEIGHT 800

using namespace sf;
using namespace std;


void setupFields(RectangleShape* fields)
{
    const Vector2f vecSize{ (float)(WINDOW_WIDTH / 8), (float)(WINDOW_HEIGHT / 8) };
    for (int i = 0; i < 64; i++)
    {
        fields[i].setSize(vecSize);
        bool isBlack = ((i / 8) + i % 8) % 2 == 0;
        if (isBlack)
            fields[i].setFillColor(Color::Black);
        else
            fields[i].setFillColor(Color::White);
        if (i == 1)
            fields[i].setFillColor(Color::Blue);

        const Vector2f vecPos{ (float)((i % 8) * WINDOW_WIDTH / 8), (float)(((63 - i) / 8) * WINDOW_HEIGHT / 8) };
        fields[i].setPosition(vecPos);

    }
}

int main()
{
    RenderWindow window{ VideoMode(WINDOW_WIDTH, WINDOW_HEIGHT), "Checkers" };
    RectangleShape* fields = new RectangleShape[64];
    setupFields(fields);
    window.setFramerateLimit(5);
    Event event;
    while (true)
    {
        window.clear(Color::Black);
        window.pollEvent(event);
        if (event.type == Event::Closed)
        {
            window.close();
            break;
        }
        for (int i = 0; i < 64; i++)
            window.draw(fields[i]);
        window.display();
    }
    delete[] fields;
    return 0;
}


