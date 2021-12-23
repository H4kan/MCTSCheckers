

#include <iostream>
#include <SFML/Graphics.hpp>
#include <SFML/Window.hpp>

#define WINDOW_WIDTH 800
#define WINDOW_HEIGHT 800
#define BOARD_SIZE 8
#define PAWN_ROWS 3
#define PAWN_SIZE 80

using namespace sf;
using namespace std;


void recolorFields(RectangleShape* fields)
{
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
    {
        bool isBlack = ((i / BOARD_SIZE) + (i % BOARD_SIZE)) % 2 == 0;
        if (isBlack)
            fields[i].setFillColor(Color::Black);
    }
}
 
void setupFields(RectangleShape* fieldShapes, int* fields)
{
    const Vector2f vecSize{ (float)(WINDOW_WIDTH / BOARD_SIZE), (float)(WINDOW_HEIGHT / BOARD_SIZE) };
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
    {
        fields[i] = -1;
        fieldShapes[i].setSize(vecSize);

        const Vector2f vecPos{ (float)((i % BOARD_SIZE) * WINDOW_WIDTH / BOARD_SIZE), 
            (float)(((BOARD_SIZE * BOARD_SIZE - 1 - i) / BOARD_SIZE) * WINDOW_HEIGHT / BOARD_SIZE) };
        fieldShapes[i].setPosition(vecPos);
    }
    recolorFields(fieldShapes);
}

void setPawnPosition(CircleShape& pawn, int row, int col)
{
    const Vector2f vecPos{ (float)(col * WINDOW_WIDTH / BOARD_SIZE + (WINDOW_WIDTH / BOARD_SIZE - PAWN_SIZE ) / 2), 
        (float)((BOARD_SIZE - 1 - row) * WINDOW_HEIGHT / BOARD_SIZE + (WINDOW_HEIGHT / BOARD_SIZE - PAWN_SIZE) / 2) };
    pawn.setPosition(vecPos);
}

void setupPawns(CircleShape* pawns, int* fields, int* rows, int* cols)
{
    for (int i = 0; i < PAWN_ROWS * BOARD_SIZE; i++)
    {
        pawns[i].setRadius(PAWN_SIZE / 2);
        pawns[i].setOutlineThickness(3);
        pawns[i].setOutlineColor(Color::Red);
        
        int row, col;
        if (i < PAWN_ROWS * BOARD_SIZE / 2)
        {
            pawns[i].setFillColor(Color::White);
            row = i / (BOARD_SIZE / 2);
            col = 2 * (i % (BOARD_SIZE / 2)) + ((i / (BOARD_SIZE / 2)) % 2);
            setPawnPosition(pawns[i], row, col);
            
        }
        else
        {
            row = BOARD_SIZE - 1 - ((i % (PAWN_ROWS * BOARD_SIZE / 2)) / (BOARD_SIZE / 2));
            col = 2 * (i % (BOARD_SIZE / 2)) + ((i / (BOARD_SIZE / 2)) % 2);
            pawns[i].setFillColor(Color::Black);
            setPawnPosition(pawns[i], row, col);
        }
        fields[row * BOARD_SIZE + col] = i;
        rows[i] = row;
        cols[i] = col;
    }
}

bool isClickInShape(Shape& shape, Vector2f clickPos)
{
    Vector2f shapePosition = shape.getPosition();
    return clickPos.x >= shapePosition.x && clickPos.x <= shapePosition.x + shape.getLocalBounds().width
        && clickPos.y >= shapePosition.y && clickPos.y <= shapePosition.y + shape.getLocalBounds().height;
}

void clearAvailableFields(bool* available)
{
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
        available[i] = false;
}


bool hasKill(int* fields, int idx, int* rows, int* cols)
{
    // white
    if (idx < PAWN_ROWS * BOARD_SIZE / 2)
    {
        if (rows[idx] < BOARD_SIZE - 2)
        {
            if (cols[idx] > 1)
            {
                if (fields[(rows[idx] + 1) * BOARD_SIZE + cols[idx] - 1] >= PAWN_ROWS * BOARD_SIZE / 2 &&
                    fields[(rows[idx] + 2) * BOARD_SIZE + cols[idx] - 2] < 0)
                    return true;
            }
            if (cols[idx] < BOARD_SIZE - 2)
            {
                if (fields[(rows[idx] + 1) * BOARD_SIZE + cols[idx] + 1] >= PAWN_ROWS * BOARD_SIZE / 2 &&
                    fields[(rows[idx] + 2) * BOARD_SIZE + cols[idx] + 2] < 0)
                    return true;
            }
        }
    }
    // black
    else
    {
        if (rows[idx] > 1)
        {
            if (cols[idx] > 1)
            {
                if (fields[(rows[idx] - 1) * BOARD_SIZE + cols[idx] - 1] < PAWN_ROWS * BOARD_SIZE / 2 &&
                    fields[(rows[idx] - 1) * BOARD_SIZE + cols[idx] - 1] >= 0 &&
                    fields[(rows[idx] - 2) * BOARD_SIZE + cols[idx] - 2] < 0)
                    return true;
            }
            if (cols[idx] < BOARD_SIZE - 2)
            {
                if (fields[(rows[idx] - 1) * BOARD_SIZE + cols[idx] + 1] < PAWN_ROWS * BOARD_SIZE / 2 &&
                    fields[(rows[idx] - 1) * BOARD_SIZE + cols[idx] + 1] >= 0 &&
                    fields[(rows[idx] - 2) * BOARD_SIZE + cols[idx] + 2] < 0)
                    return true;
            }
        }
    }
    return false;
}

void setAvailableFields(int row, int col, bool isWhite, bool* available, int* fields)
{
    if (isWhite && row < BOARD_SIZE - 1)
    {
        if (col > 0 && fields[(row + 1) * BOARD_SIZE + col - 1] < 0)
        {
            available[(row + 1) * BOARD_SIZE + col - 1] = true;
        }
        if (col < BOARD_SIZE - 1 && fields[(row + 1) * BOARD_SIZE + col + 1] < 0)
        {
            available[(row + 1) * BOARD_SIZE + col + 1] = true;
        } 
    }
    else if (!isWhite && row > 0)
    {
        if (col > 0 && fields[(row - 1) * BOARD_SIZE + col - 1] < 0)
        {
            available[(row - 1) * BOARD_SIZE + col - 1] = true;
        }
        if (col < BOARD_SIZE - 1 && fields[(row - 1) * BOARD_SIZE + col + 1] < 0)
        {
            available[(row - 1) * BOARD_SIZE + col + 1] = true;
        }
    }
}

void setAvailableKills(int* fields, int row, int col, bool isWhite, bool* available)
{
    if (isWhite)
    {
        if (col > 1)
        {
            available[(row + 2) * BOARD_SIZE + col - 2] = 
                fields[(row + 2) * BOARD_SIZE + col - 2] < 0 &&
                fields[(row + 1) * BOARD_SIZE + col - 1] >= PAWN_ROWS * BOARD_SIZE / 2;
        }
        if (col < BOARD_SIZE - 1)
        {
            available[(row + 2) * BOARD_SIZE + col + 2] =
                fields[(row + 2) * BOARD_SIZE + col + 2] < 0 &&
                fields[(row + 1) * BOARD_SIZE + col + 1] >= PAWN_ROWS * BOARD_SIZE / 2;
        }
    }
    else if (!isWhite)
    {
        if (col > 1)
        {
            available[(row - 2) * BOARD_SIZE + col - 2] =
                fields[(row - 2) * BOARD_SIZE + col - 2] < 0 &&
                fields[(row - 1) * BOARD_SIZE + col - 1] >= 0 &&
                fields[(row - 1) * BOARD_SIZE + col - 1] < PAWN_ROWS * BOARD_SIZE / 2;
        }
        if (col < BOARD_SIZE - 1)
        {
            available[(row - 2) * BOARD_SIZE + col + 2] =
                fields[(row - 2) * BOARD_SIZE + col + 2] < 0 &&
                fields[(row - 1) * BOARD_SIZE + col + 1] >= 0 &&
                fields[(row - 1) * BOARD_SIZE + col + 1] < PAWN_ROWS * BOARD_SIZE / 2;
        }
    }
}

void markAvailableFields(RectangleShape* fieldShapes, bool* available)
{
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
    {
        if (available[i])
            fieldShapes[i].setFillColor(Color::Color(125, 125, 125));
    }
}

void removePawn(int row, int col, int* rows, int* cols, int* fields, CircleShape* pawns)
{
    int targetIdx = fields[row * BOARD_SIZE + col];
    rows[targetIdx] = -1;
    cols[targetIdx] = -1;
    pawns[targetIdx].setRadius(0);
    fields[row * BOARD_SIZE + col] = -1;
}

void handlePawnClick(int i, int* rows, int* cols, int* fields, RectangleShape* fieldShapes, bool* available, 
    int& selectedPawnIdx, bool& performedOperation, bool isThereKill, bool* pawnHasKill)
{
    clearAvailableFields(available);
    if (!isThereKill)
        setAvailableFields(rows[i], cols[i], i < (PAWN_ROWS* BOARD_SIZE / 2),
            available, fields);
    if (pawnHasKill[i])
        setAvailableKills(fields, rows[i], cols[i], i < (PAWN_ROWS* BOARD_SIZE / 2), available);
    markAvailableFields(fieldShapes, available);
    selectedPawnIdx = i;
    performedOperation = true;
}

void markQueen(CircleShape* pawns, int idx)
{
    pawns[idx].setOutlineColor(Color::Yellow);
}

int main()
{
    RenderWindow window{ VideoMode(WINDOW_WIDTH, WINDOW_HEIGHT), "Checkers" };
    RectangleShape* fieldShapes = new RectangleShape[BOARD_SIZE * BOARD_SIZE];
    CircleShape* pawns = new CircleShape[PAWN_ROWS * BOARD_SIZE];
    int* fields = new int[BOARD_SIZE * BOARD_SIZE];
    int* rows = new int[PAWN_ROWS * BOARD_SIZE];
    int* cols = new int[PAWN_ROWS * BOARD_SIZE];
    bool* pawnHasKill = new bool[PAWN_ROWS * BOARD_SIZE];
    bool* available = new bool[BOARD_SIZE * BOARD_SIZE];
    bool* isQueen = new bool[PAWN_ROWS * BOARD_SIZE];
    int selectedPawnIdx = -1;
    bool performedOperation = false;
    bool blackTurn = false;
    setupFields(fieldShapes, fields);
    setupPawns(pawns, fields, rows, cols);
    
    window.setFramerateLimit(25);
    Event event;

    bool isThereKill = false;
    while (true)
    {
        window.clear(Color::Black);
        window.pollEvent(event);
        if (event.type == Event::Closed)
        {
            window.close();
            break;
        }
        else if (event.type == Event::MouseButtonPressed)
        {
            performedOperation = false;
            recolorFields(fieldShapes);
            Vector2f mousePosition = (Vector2f)Mouse::getPosition(window);

            if (!blackTurn)
                for (int i = 0; i < PAWN_ROWS * BOARD_SIZE / 2; i++)
                {
                    if (isClickInShape(pawns[i], mousePosition))
                    {
                        handlePawnClick(i, rows, cols, fields, fieldShapes, available, selectedPawnIdx, performedOperation, isThereKill, pawnHasKill);
                        break;
                    }
                }
            else
                for (int i = PAWN_ROWS * BOARD_SIZE / 2; i < PAWN_ROWS * BOARD_SIZE; i++)
                {
                    if (isClickInShape(pawns[i], mousePosition))
                    {
                        handlePawnClick(i, rows, cols, fields, fieldShapes, available, selectedPawnIdx, performedOperation, isThereKill, pawnHasKill);
                        break;
                    }
                }
            
            if (!performedOperation && selectedPawnIdx >= 0)
            {
                for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
                {
                    if (available[i] && isClickInShape(fieldShapes[i], mousePosition))
                    {
                        setPawnPosition(pawns[selectedPawnIdx], i / BOARD_SIZE, i % BOARD_SIZE);
                        if (i / BOARD_SIZE - rows[selectedPawnIdx] > 1 || i / BOARD_SIZE - rows[selectedPawnIdx] < -1)
                        {
                            removePawn((rows[selectedPawnIdx] + i / BOARD_SIZE) / 2, (cols[selectedPawnIdx] + (i % BOARD_SIZE)) / 2,
                                rows, cols, fields, pawns);
                        }
                        fields[rows[selectedPawnIdx] * BOARD_SIZE + cols[selectedPawnIdx]] = -1;
                        fields[i] = selectedPawnIdx;
                        rows[selectedPawnIdx] = i / BOARD_SIZE;
                        cols[selectedPawnIdx] = i % BOARD_SIZE;
                        if ((selectedPawnIdx >= PAWN_ROWS * BOARD_SIZE / 2
                            && rows[selectedPawnIdx] == 0) ||
                            (selectedPawnIdx < PAWN_ROWS * BOARD_SIZE / 2 &&
                                rows[selectedPawnIdx] == BOARD_SIZE - 1))
                        {
                            markQueen(pawns, selectedPawnIdx);
                            isQueen[selectedPawnIdx] = true;   
                        }
                        selectedPawnIdx = -1;
                        clearAvailableFields(available);
                        blackTurn = !blackTurn;
                        isThereKill = false;
                        if (!blackTurn)
                        {
                            for (int i = 0; i < PAWN_ROWS * BOARD_SIZE / 2; i++)
                            {
                                pawnHasKill[i] = rows[i] >= 0 && hasKill(fields, i, rows, cols);
                                if (pawnHasKill[i])
                                    isThereKill = true;
                            }
                        }
                        else
                        {
                            for (int i = PAWN_ROWS * BOARD_SIZE / 2; i < PAWN_ROWS * BOARD_SIZE; i++)
                            {
                                pawnHasKill[i] = rows[i] >= 0 && hasKill(fields, i, rows, cols);
                                if (pawnHasKill[i])
                                    isThereKill = true;
                            }
                        }
                        break;
                    }
                }
            }
            event.type = Event::MouseButtonReleased;
        }

        for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
            window.draw(fieldShapes[i]);
        for (int i = 0; i < PAWN_ROWS * BOARD_SIZE; i++)
            window.draw(pawns[i]);
        
        window.display();
    }
    delete[] fields;
    delete[] pawns;
    return 0;
}